#!/bin/bash

#This script needs aws cli tools to deploy a lambda function on S3

S3BUCKET=$1
S3KEY=$2
STACK_NAME=$3
REGION=$4

LAMBDA_FUNCTION="rb_cfn_delete_route53_entries.zip"

function help() {
  echo "test.sh <S3BUCKET> <S3KEY>"
  echo "  - S3BUCKET: bucket where put lambda function"
  echo "  - S3KEY: path inside bucket where put lambda function"
  echo "  - STACK_NAME: name of the cloudformation stack for testing"
  echo "  - REGION: region in which create cloudformation stack"
}

if [ "x$S3BUCKET" != "x" -a "x$S3KEY" != "x" -a "x$STACK_NAME" != "x" ] ; then
  SCRIPT=$(realpath $0)
  SCRIPTPATH=$(dirname $SCRIPT)
  pushd $SCRIPTPATH &> /dev/null

  echo -n "Installing dependencies... "
  pushd .. &> /dev/null
  npm install > /dev/null
  popd &> /dev/null
  echo "ok"

  echo -n "Generating lambda function package... "
  zip -r $LAMBDA_FUNCTION ../index.js ../node_modules > /dev/null
  if [ $? -eq 0 ] ; then echo "ok" ; else echo "FAILED!!"; popd &>/dev/null ; exit 1 ; fi

  echo -n "Uploading lambda function to s3 ($S3BUCKET/$S3KEY)... "
  aws s3 cp $LAMBDA_FUNCTION s3://$S3BUCKET/$S3KEY/$LAMBDA_FUNCTION > /dev/null
  aws s3 cp test_cf.template s3://$S3BUCKET/$S3KEY/test_cf.template > /dev/null
  if [ $? -eq 0 ] ; then echo "ok" ; else echo "FAILED!!" ; popd &>/dev/null ; exit 2 ; fi

  echo -n "Creating cloudformation stack for testing... "
  aws cloudformation create-stack --stack-name $STACK_NAME \
    --template-url https://s3-$REGION.amazonaws.com/$S3BUCKET/$S3KEY/test_cf.template \
    --capabilities CAPABILITY_IAM --parameters \
    ParameterKey=BucketOfLambdaFuncion,ParameterValue=$S3BUCKET \
    ParameterKey=PathOfLambdaFunction,ParameterValue=$S3KEY --region $REGION > /dev/null
  if [ $? -eq 0 ] ; then
    echo "ok"
    echo -n "Waiting until stack is completely created... "
    aws cloudformation wait stack-create-complete --stack-name $STACK_NAME
    echo "ok"
  else
    echo "Stack creation FAILED!!"
  fi

  echo -n "Cleaning stack..."
  aws cloudformation delete-stack --stack-name $STACK_NAME
  echo "ok"
  echo -n "Waiting until stack is completely deleted... "
  aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME
  TEST_STATUS=$?
  echo "ok"
  popd &>/dev/null
  [ "x$TEST_STATUS" != "x" ] && exit $TEST_STATUS
  exit 4
else
  help;
fi
