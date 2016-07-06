/**
 *  Lambda function for redBorder CloudFormation templates. It's used to Delete
 *  route53 entries when stack is being destroyed.
 */

var aws = require('aws-sdk');
var response = require('cfn-response');
var async = require('async');

var route53 = new aws.Route53();

var changeResourceRecordSets = function (route53params) {
    return function (callback) {
        route53.changeResourceRecordSets(route53params, function(err, data) {
            callback(err, data);
        });
    };
};

var deleteEntry = function(resourceRecord, callback) {
    //Generating query
    if (resourceRecord.Type === 'A' && resourceRecord.AliasTarget === undefined) {
        var route53params = {
            HostedZoneId: resourceRecord.HostedZoneId,
            ChangeBatch: {
                Changes: [ {
                    Action: 'DELETE',
                    ResourceRecordSet: {
                        Name: resourceRecord.Name,
                        Type: resourceRecord.Type,
                        TTL: resourceRecord.TTL,
                        ResourceRecords: [ {
                            Value: resourceRecord.ResourceRecords[0].Value
                        } ]
                    }
                } ]
            }
        };
        async.retry({times: 3, interval: 50}, changeResourceRecordSets(route53params), function(err, data) {
            callback(err, data);
        });
    } else {
        //If type != A, result is ok, nothing to do.
        callback(null, null);
    }
};

var listEntries = function(HostedZone, callback) {
    var listParams = {
        HostedZoneId: HostedZone,
    };
    route53.listResourceRecordSets(listParams, function(err, data) {
        if (err) {
            console.log("Error getting listResourceRecordSets");
            callback(err, data);
        } else {
            //Make queries for delete A entries asyncronously
            //First enrich resourceRecordSet with HostedZoneId
            data.ResourceRecordSets.forEach(function (recordSet, index, array) {
                recordSet.HostedZoneId = HostedZone;
            });
            //Then send queries asyncronously
            async.mapSeries(data.ResourceRecordSets, deleteEntry, function(err, results) {
                callback(err, data);
            });
        }
    });
};

exports.handler = function(event, context) {
    //This function only must be executed if stack is being destroyed
    if (event.RequestType === 'Delete') {
        var HostedZones = [event.ResourceProperties.PublicHostedZone, event.ResourceProperties.PrivateHostedZone];
        async.map(HostedZones, listEntries, function(err, results) {
            if (err) {
                console.log("Error in lambda function", err.stack);
                response.send(event, context, response.FAILED);
            } else {
                response.send(event, context, response.SUCCESS);
            }
        });
    } else {
        response.send(event, context, response.SUCCESS);
    }
};
