variable "environment_name" {
  type        = string
  description = "The Name of the environment"
}

variable "stage" {
  description = "The stage of the Environment (dev, test, prod)"
  type        = string
}

variable "project" {
  description = "The Project Name"
  type        = string
  default     = "JOMS"
}

variable "functional_area" {
  description = "The Functional Area of the environment (AFMC)"
  type        = string
}

variable "location" {
  description = "The Azure location where resources will be created."
  type        = string
}
