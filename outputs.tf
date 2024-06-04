output "container_password" {
  value     = random_password.lxc_password.result
  sensitive = true
}
output "container_private_key" {
  value     = tls_private_key.ubuntu_container_key.private_key_pem
  sensitive = true
}
