resource "aws_sfn_state_machine" "procesar_pedido" {
  name     = "${var.proyecto}-procesar-pedido"
  type     = "STANDARD"
  role_arn = data.aws_iam_role.lab.arn

  definition = templatefile("${path.module}/statemachines/procesar-pedido.asl.json.tftpl", {
    crear_pedido_arn = module.crear_pedido.arn
  })
}
