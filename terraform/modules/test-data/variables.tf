variable "data_size_gb" {
  type    = number
  default = 1
}

variable "vscode_instance_id" {
  type = string
}

variable "pg_host" {
  type = string
}

variable "mongo_host" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
