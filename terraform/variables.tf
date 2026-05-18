variable "ssh_public_key" {
    description = "Public key to access the provisionned VM"
    type = string
}

variable "hashed_password"{
    description = "Password for the user alpine"
    type = string
}