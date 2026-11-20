# Frontend en AWS Amplify Hosting.
#
# Se eligio sobre S3 + CloudFront porque el Learner Lab niega CloudFront, y un
# sitio estatico de S3 solo sirve HTTP: sin HTTPS el navegador no ofrece
# crypto.randomUUID ni la geolocalizacion, que usan las apps. Amplify sirve por
# HTTPS con su propio dominio, distribuido por una CDN que administra AWS.
#
# La app no se conecta al repositorio (necesitaria un token de GitHub): el
# workflow de deploy compila el frontend con los outputs de este apply y sube
# el zip con un despliegue manual (scripts/publicar-frontend.sh).
resource "aws_amplify_app" "frontend" {
  name     = "${var.proyecto}-frontend"
  platform = "WEB"

  # SPA: toda ruta sin extension (/cliente, /repartidor/pedido...) devuelve
  # index.html y la resuelve React Router. Un archivo inexistente sigue en 404.
  custom_rule {
    source = "</^[^.]+$|\\.(?!(css|gif|ico|jpg|jpeg|js|png|txt|svg|woff|woff2|ttf|map|json|webp|webmanifest)$)([^.]+$)/>"
    target = "/index.html"
    status = "200"
  }
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.frontend.id
  branch_name = "main"
  stage       = "PRODUCTION"
}

locals {
  frontend_url = "https://${aws_amplify_branch.main.branch_name}.${aws_amplify_app.frontend.default_domain}"

  # Origenes que pueden llamar a la API y subir comprobantes: el frontend
  # publicado mas los de var.cors_origenes (localhost para desarrollo).
  cors_origenes = distinct(concat([local.frontend_url], var.cors_origenes))
}
