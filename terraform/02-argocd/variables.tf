## not needed when using remote state to fetch outputs
#
#variable "cluster_endpoint" {
#  description = "The endpoint for the EKS cluster API."
#  type        = string
#}
#
#variable "cluster_certificate_authority_data" {
#  description = "The certificate authority data for the EKS cluster."
#  type        = string
#}
#
#variable "cluster_name" {
#  description = "The name of the EKS cluster."
#  type        = string
#}
#
#variable "region" {
#  description = "The AWS region where the EKS cluster is deployed."
#  type        = string
#}
#
#variable "name" {
#  description = "The cluster name."
#  type        = string
#}
#
#variable "access_entries" {
#  description = "Security group entries that allow access to the EKS cluster."
#  type        = any
#}
#
#variable "access_policy_associations" {
#  description = "IAM policy associations required for EKS access."
#  type        = any
#}