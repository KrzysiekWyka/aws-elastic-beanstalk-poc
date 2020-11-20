terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}


provider "aws" {
  region = "REGION"
  access_key="ACCESS_KEY"
  secret_key="SECRET_KEY"
}

resource "aws_elastic_beanstalk_application" "tftest" {
  name        = "tf-test-name"
  description = "tf-test-desc"
}

resource "aws_iam_role" "elb-role" {
  name_prefix = "tf-test-role"
  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "elb-profile" {
  name_prefix = "tf-test-elb-profile"
  role = aws_iam_role.elb-role.name
}

resource "aws_s3_bucket" "s3-bucket" {
  bucket = "my-test-bucket-for-ebs"
  acl    = "private"
}

resource "aws_iam_policy" "s3-full-access" {
  name = "S3-full-access"
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:PutAccountPublicAccessBlock",
                "s3:GetAccountPublicAccessBlock",
                "s3:ListAllMyBuckets",
                "s3:HeadBucket"
            ],
            "Resource": "*"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::*/*",
                "${aws_s3_bucket.s3-bucket.arn}"
            ]
        },
        {
            "Sid": "CloudWatchLogsAccess",
            "Action": [
                "logs:PutLogEvents",
                "logs:CreateLogStream",
                "logs:DescribeLogStreams",
                "logs:DescribeLogGroups"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
POLICY
}

resource "aws_iam_policy_attachment" "s3-full-access-attach" {
  name = "s3-full-access"
  roles = [aws_iam_role.elb-role.name]
  policy_arn = aws_iam_policy.s3-full-access.arn
}

resource "aws_s3_bucket_object" "object" {
  bucket = aws_s3_bucket.s3-bucket.id
  key    = "latest.zip"
  source = "latest.zip"
  etag = filemd5("latest.zip")
}

resource "aws_elastic_beanstalk_application_version" "latest" {
  name        = "latest"
  application = aws_elastic_beanstalk_application.tftest.name
  description = "Version latest of app ${aws_elastic_beanstalk_application.tftest.name}"
  bucket      = aws_s3_bucket.s3-bucket.id
  key         = aws_s3_bucket_object.object.id
}

resource "aws_elastic_beanstalk_environment" "tfenvtest" {
  name                = "tf-test-name"
  application         = aws_elastic_beanstalk_application.tftest.name
  solution_stack_name = "64bit Amazon Linux 2018.03 v2.16.1 running Docker 19.03.6-ce"
  version_label = aws_elastic_beanstalk_application_version.latest.name
  
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.elb-profile.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t2.micro"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application"
    name      = "Application Healthcheck URL"
    value     = "/"
  }

  setting {
    namespace = "aws:elasticbeanstalk:cloudwatch:logs"
    name      = "StreamLogs"
    value     = true
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "ENV_NAME"
    value     = "ENV_VALUE"
  }
}