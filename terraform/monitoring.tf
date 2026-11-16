# ---------------------------------------------------------------------------
# Observabilidad: SNS (correo) + 3 alarmas + dashboard de CloudWatch
#
# Las alarmas y el dashboard NO se escriben aquí a mano: se leen de
# alerting/alarms.json y alerting/cloudwatch-dashboard.json. Terraform solo
# rellena los valores que cambian en cada despliegue (${instance_id},
# ${region}, ${account_id}) con templatefile(). Así la configuración vive en
# un archivo legible y, como lo crea Terraform, sobrevive a los resets del lab.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  alerting_dir = "${path.module}/../alerting"

  template_vars = {
    instance_id = aws_instance.todo_api.id
    region      = var.aws_region
    account_id  = data.aws_caller_identity.current.account_id
  }

  # Mapa nombre → definición, para crear una alarma por cada elemento con for_each.
  # Ojo: se lee con file() (no templatefile) porque las CLAVES de for_each deben
  # conocerse en el plan, y en un provision desde cero el instance_id aún no
  # existe. El placeholder solo se sustituye dentro de `dimensions` (abajo).
  alarms = {
    for alarm in jsondecode(file("${local.alerting_dir}/alarms.json")).alarms :
    alarm.name => alarm
  }
}

# --- SNS: un tópico, una suscripción por correo ------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

# AWS manda un correo de confirmación: hasta que se da clic en "Confirm
# subscription" la suscripción queda PendingConfirmation y no llegan alertas.
# Si no se define alert_email, se omite (count = 0) para no romper el apply.
resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- Alarmas (una por métrica) -----------------------------------------------

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name = each.value.name
  # La justificación y la acción viajan en la descripción: llegan en el correo de SNS
  alarm_description = substr(
    "${each.value.description} | Por qué este umbral: ${each.value.justificacion} | Qué hacer: ${each.value.accion}",
    0, 1024
  )

  namespace   = each.value.namespace
  metric_name = each.value.metric_name
  # "${instance_id}" del JSON → ID real de la EC2 ($$ = "$" literal en HCL)
  dimensions = {
    for key, value in each.value.dimensions :
    key => replace(value, "$${instance_id}", local.template_vars.instance_id)
  }
  statistic           = try(each.value.statistic, null)
  extended_statistic  = try(each.value.extended_statistic, null)
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  treat_missing_data  = each.value.treat_missing_data

  # Avisar cuando entra en ALARM y también cuando se recupera (OK)
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# --- Dashboard -----------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"
  # decode + encode: valida que el JSON resultante sea correcto y lo normaliza
  dashboard_body = jsonencode(jsondecode(templatefile("${local.alerting_dir}/cloudwatch-dashboard.json", local.template_vars)))

  # El widget de alarmas referencia las alarmas por ARN: crearlas primero
  depends_on = [aws_cloudwatch_metric_alarm.this]
}
