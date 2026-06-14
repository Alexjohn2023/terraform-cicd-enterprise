variable "environment" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "instance_count" {
  type    = number
  default = 1
}

variable "aws_region" {
  type = string
}
