variable "aws_region" {
  type = string
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "db_name" {
  type    = string
  default = "nova"
}

variable "db_user" {
  type    = string
  default = "postgres"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "kodekey_base_url" {
  type = string
}

variable "kodekey_api_key" {
  type      = string
  sensitive = true
}

variable "searxng_secret_key" {
  type      = string
  sensitive = true
}

variable "openrouter_model" {
  type    = string
  default = "openai/gpt-5-mini"
}

variable "model_planner" {
  type    = string
  default = "gpt-5.4-mini"
}

variable "model_research" {
  type    = string
  default = "gpt-5.4-mini"
}

variable "model_competitor" {
  type    = string
  default = "claude-haiku-4-5-20251001"
}

variable "model_market" {
  type    = string
  default = "qwen/qwen3.7-plus"
}

variable "model_customer" {
  type    = string
  default = "gpt-5.4-mini"
}

variable "model_pricing" {
  type    = string
  default = "gpt-5.4-mini"
}

variable "model_advisor" {
  type    = string
  default = "claude-sonnet-5"
}

variable "model_chat" {
  type    = string
  default = "gpt-5.4-mini"
}
