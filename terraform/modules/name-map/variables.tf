variable "environment_name" {
  type        = string
  description = "The Name of the environment"
}

variable "parent_module" {
  description = "The name of the Parent Terraform Module."
  type        = string
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

variable "c1_project" {
  description = "The C1 Project Name"
  type        = string
  default     = "JOMSMVP"
}

variable "functional_area" {
  description = "The Functional Area of the environment (AFMC)"
  type        = string
}

variable "location" {
  description = "The Azure location where resources will be created."
  type        = string
}