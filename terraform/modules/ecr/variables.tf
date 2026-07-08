variable "repository_name" {
  description = "Name of the ECR repository for the FinBank app image."
  type        = string
  default     = "finbank-digital"
}

variable "image_tag_mutability" {
  description = "IMMUTABLE prevents overwriting a tag once pushed. Good hygiene: a given tag always means the same image. Use MUTABLE only if you deliberately re-push :latest."
  type        = string
  default     = "IMMUTABLE"
}

variable "force_delete" {
  description = "Allow `terraform destroy` to delete the repo even if it still holds images. True keeps teardown painless on a practice account."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the repository."
  type        = map(string)
  default = {
    Project = "finbank-digital"
    Env     = "dev"
  }
}
