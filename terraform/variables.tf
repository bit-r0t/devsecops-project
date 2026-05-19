variable "ssh_public_key" {
  description = "Public key to access the provisionned VM"
  type        = string
}

variable "hashed_passwd" {
  description = "Password for the user alpine"
  type        = string
}