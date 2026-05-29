variable "env" {}

resource "aws_sqs_queue" "api_logs" {
  name                      = "queue-api-logs-${var.env}"
  message_retention_seconds = 86400
  tags                      = { Name = "queue-api-logs-${var.env}" }
}

resource "aws_sqs_queue" "security_alerts" {
  name                      = "queue-security-alerts-${var.env}"
  message_retention_seconds = 86400
  tags                      = { Name = "queue-security-alerts-${var.env}" }
}

output "api_logs_queue_url" { value = aws_sqs_queue.api_logs.url }
output "security_alerts_queue_url" { value = aws_sqs_queue.security_alerts.url }
output "api_logs_queue_name" { value = aws_sqs_queue.api_logs.name }
output "security_alerts_queue_name" { value = aws_sqs_queue.security_alerts.name }
