terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
  backend "s3" {
    bucket                      = "config"
    key                         = "exemplo-aws-api-gateway.tfstate"
    access_key                  = "teste"
    secret_key                  = "teste"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
    endpoint                    = "http://localhost:4566"
    sts_endpoint                = "http://localhost:4566"
  }
}

provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_force_path_style         = true

  endpoints {
    apigateway = "http://localhost:4566"
    cloudwatch = "http://localhost:4566"
    iam        = "http://localhost:4566"
    lambda     = "http://localhost:4566"
    s3         = "http://localhost:4566"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "myapi"
}

resource "aws_api_gateway_resource" "resource" {
  path_part   = "resource"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.demo.id
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda.invoke_arn
}

# Lambda
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "arn:aws:execute-api:us-east-1:111111111111:${aws_api_gateway_rest_api.api.id}/*/${aws_api_gateway_method.method.http_method}${aws_api_gateway_resource.resource.path}"
}

data "archive_file" "lambda" {
    type = "zip"
    output_path = "lambdas/dist/api_test.zip"
    source_dir = "lambdas/api-test"
}


resource "aws_lambda_function" "lambda" {
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  function_name = "mylambda"
  role          = aws_iam_role.role.arn
  handler       = "index.handler"
  runtime          = "nodejs14.x"
}

# IAM
resource "aws_iam_role" "role" {
  name = "myrole"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

// AUTH FUNC HERE

resource "aws_api_gateway_authorizer" "demo" {
  name                   = "demo"
  rest_api_id            = "${aws_api_gateway_rest_api.api.id}"
  authorizer_uri         = aws_lambda_function.lambda_auth.invoke_arn
#   authorizer_credentials = aws_iam_role.invocation_role.arn
  type = "REQUEST"
}

resource "aws_iam_role" "invocation_role" {
  name = "api_gateway_auth_invocation"
  path = "/resource"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "invocation_policy" {
  name = "default"
  role = aws_iam_role.invocation_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "lambda:InvokeFunction",
      "Effect": "Allow",
      "Resource": "${aws_lambda_function.lambda_auth.arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role" "lambda_auth" {
  name = "demo-lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

data "archive_file" "lambda_auth" {
    type = "zip"
    output_path = "lambdas/dist/authorizer.zip"
    source_dir = "lambdas/authorizer"
}


resource "aws_lambda_function" "lambda_auth" {
  filename         = data.archive_file.lambda_auth.output_path
  source_code_hash = data.archive_file.lambda_auth.output_base64sha256
  function_name = "api_gateway_authorizer"
  role          = aws_iam_role.lambda_auth.arn
  handler       = "index.handler"
  runtime          = "nodejs14.x"
}