
variable "region" {
  description = ""
  default = "ap-southeast-2"  
}
variable "environment" {
  description = ""
  default = "test"  
}

variable "project" {
  description = "project name"
  default = "lhb-test"  
}



variable "lookup-region_abbr" {
  description = "AWS Region: Abbreviation Lookup"
  type = map
  default = {
    ap-east-1      = "ape1"
    ap-northeast-1 = "apne1"
    ap-northeast-2 = "apne2"
    ap-south-1     = "aps1"
    ap-southeast-1 = "apse1"
    ap-southeast-2 = "apse2"
    ca-central-1   = "cac1"
    eu-central-1   = "euc1"
    eu-north-1     = "eun1"
    eu-west-1      = "euw1"
    eu-west-2      = "euw2"
    eu-west-3      = "euw3"
    me-south-1     = "mes1"
    sa-east-1      = "sae1"
    us-east-1      = "use1"
    us-east-2      = "use2"
    us-west-1      = "usw1"
    us-west-2      = "usw2"
    us-gov-east-1  = "uge1"
    us-gov-west-1	 = "ugw1"
  }
}