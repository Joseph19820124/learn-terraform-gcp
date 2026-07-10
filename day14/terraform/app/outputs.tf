output "caller_url" {
  value = aws_ecs_express_gateway_service.caller.ingress_paths[0].endpoint
}

output "callee_url" {
  value = aws_ecs_express_gateway_service.callee.ingress_paths[0].endpoint
}
