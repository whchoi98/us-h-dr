variable "requester_tgw_id" {
  description = "Transit Gateway ID of the requester"
  type        = string
}

variable "requester_tgw_route_table_id" {
  description = "Route table ID of the requester TGW"
  type        = string
}

variable "accepter_tgw_id" {
  description = "Transit Gateway ID of the accepter"
  type        = string
}

variable "accepter_tgw_route_table_id" {
  description = "Route table ID of the accepter TGW"
  type        = string
}

variable "accepter_region" {
  description = "AWS region of the accepter TGW"
  type        = string
}

variable "requester_cidrs_to_route" {
  description = "CIDRs to route from requester to accepter via peering"
  type        = list(string)
}

variable "accepter_cidrs_to_route" {
  description = "CIDRs to route from accepter to requester via peering"
  type        = list(string)
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
