output "backend_url" {
  description = "The public URL of the backend API load balancer."
  value       = module.medusajs.backend_url
}
