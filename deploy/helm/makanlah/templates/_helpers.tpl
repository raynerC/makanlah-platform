{{- define "makanlah.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{ .Values.serviceAccount.name }}
{{- else -}}
default
{{- end -}}
{{- end -}}

{{- define "makanlah.labels" -}}
app.kubernetes.io/part-of: makanlah
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
