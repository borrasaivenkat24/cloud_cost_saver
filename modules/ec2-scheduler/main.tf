variable "name" {
  type = string
}

variable "lambda_source" {
  type = string
}

variable "schedule" {
  type = string
}

variable "target_tag_value" {
  type = string
}

variable "site_bucket_name" {
  type = string
}

variable "site_bucket_arn" {
  type = string
}

variable "alert_email" {
  type      = string
  sensitive = true
}

# ---------- Notifications ----------
resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------- IAM ----------
resource "aws_iam_role" "lambda" {
  name = "${var.name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "permissions" {
  name = "scheduler-permissions"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ec2:DescribeInstances"
        Resource = "*"
      },
      {
        # Can only stop instances that carry the target tag
        Effect   = "Allow"
        Action   = "ec2:StopInstances"
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/Environment" = var.target_tag_value }
        }
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${var.site_bucket_arn}/status.json"
      }
    ]
  })
}

# ---------- Lambda ----------
data "archive_file" "lambda" {
  type        = "zip"
  source_file = var.lambda_source
  output_path = "${path.root}/build/stop_instances.zip"
}

resource "aws_lambda_function" "stop" {
  function_name    = "${var.name}-stop"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "stop_instances.handler"
  timeout          = 30
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      TARGET_TAG_VALUE = var.target_tag_value
      BUCKET_NAME      = var.site_bucket_name
      TOPIC_ARN        = aws_sns_topic.alerts.arn
    }
  }
}

# ---------- Schedule (EventBridge) ----------
resource "aws_cloudwatch_event_rule" "nightly" {
  name                = "${var.name}-schedule"
  schedule_expression = var.schedule
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.nightly.name
  arn  = aws_lambda_function.stop.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.nightly.arn
}

# ---------- Monitoring ----------
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${var.name}-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.stop.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

output "function_name" {
  value = aws_lambda_function.stop.function_name
}