{{- define "cf-lb-controller.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cf-lb-controller.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "cf-lb-controller.name" . -}}
{{- end -}}
{{- end -}}

{{- define "cf-lb-controller.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "cf-lb-controller.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "cf-lb-controller.webhookEnabled" -}}
{{- $defaultHook := dict -}}
{{- $hooks := .Values.webhook.webhooks | default (list $defaultHook) -}}
{{- $labelEnabled := "true" -}}
{{- if hasKey .Values.webhook "labels" -}}
  {{- if hasKey .Values.webhook.labels "cf-lb-enabled" -}}
    {{- $labelEnabled = printf "%v" (index .Values.webhook.labels "cf-lb-enabled") -}}
  {{- end -}}
{{- end -}}
{{- if and (gt (len $hooks) 0) (eq (lower $labelEnabled) "true") -}}true{{- else -}}false{{- end -}}
{{- end -}}
