terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

locals {
  emails = ["tulani.service@gmail.com"]
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_dynamodb_table" "adoption_table" {
  name           = "dog_adoption"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "dogid"
  stream_enabled    = true
  stream_view_type  = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "dogid"
    type = "S"
  }

#   attribute {
#     name = "dogname"
#     type = "S"
#   }

  attribute {
    name = "adopted"
    type = "S"
  }

  global_secondary_index {
    name               = "adopted-index"
    hash_key           = "adopted"
    projection_type    = "ALL"
  }

  tags = {
    Name        = "adoption-table-of-dogs"
    Environment = "portfolio"
  }
  
}
resource "aws_lambda_event_source_mapping" "adoption_mapping" {
  event_source_arn = aws_dynamodb_table.adoption_table.stream_arn
  function_name    = aws_lambda_function.adopt_lambda.arn
  starting_position = "LATEST"
  # batch_size = 1
}


resource "aws_sns_topic" "adoption_topic" {
  name= "myAlert"
}

resource "aws_sns_topic_subscription" "email_adoption" {
  count     = length(local.emails)
  topic_arn = aws_sns_topic.adoption_topic.arn
  protocol  = "email"
  endpoint  = local.emails[count.index]
}

resource "aws_iam_role" "lambda_role" {
name   = "adoption_role"
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

resource "aws_iam_policy" "iam_policy_for_lambda" {
 
 name         = "adoption-policy"
 path         = "/"
 description  = "AWS IAM Policy for managing aws lambda role"
 policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": [
       "logs:CreateLogGroup",
       "logs:CreateLogStream",
       "logs:PutLogEvents",
       "SNS:Publish"
     ],
     "Resource": "arn:aws:logs:*:*:*",
     "Effect": "Allow"
   }
 ]
}
EOF
}
resource "aws_iam_role_policy" "dynamodb_lambda_policy" {
  name   = "lambda-dynamodb-policy"
  role   = aws_iam_role.lambda_role.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Sid": "AllowLambdaFunctionToCreateLogs",
        "Action": [ 
            "logs:*" 
        ],
        "Effect": "Allow",
        "Resource": [ 
            "arn:aws:logs:*:*:*" 
        ]
    },
    {
        "Sid": "AllowLambdaFunctionInvocation",
        "Effect": "Allow",
        "Action": [
            "lambda:InvokeFunction"
        ],
        "Resource": [
            "${aws_dynamodb_table.adoption_table.arn}/stream/*"
        ]
    },
    {
        "Sid": "APIAccessForDynamoDBStreams",
        "Effect": "Allow",
        "Action": [
            "dynamodb:GetRecords",
            "dynamodb:GetShardIterator",
            "dynamodb:DescribeStream",
            "dynamodb:ListStreams"
        ],
        "Resource": "${aws_dynamodb_table.adoption_table.arn}/stream/*"
    }
  ]
}
EOF
}

resource "aws_lambda_function" "adopt_lambda" {
  filename         = "main.zip"
  function_name    = "lambda_function"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "main.lambda_handler"
  runtime          = "python3.8"
  timeout          = 10
  memory_size      = 128
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_exec.name
}


