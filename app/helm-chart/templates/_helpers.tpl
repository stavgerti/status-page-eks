{{/*
Full resource name prefix, e.g. "my-release-status-page".
*/}}
{{- define "status-page.fullname" -}}
{{ .Release.Name }}-status-page
{{- end -}}

{{/*
Common labels applied to every resource.
*/}}
{{- define "status-page.labels" -}}
app.kubernetes.io/name: status-page
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Selector labels for one component (web/worker/scheduler/migrate).
Usage: {{ include "status-page.selectorLabels" (dict "root" . "component" "web") | nindent 4 }}
*/}}
{{- define "status-page.selectorLabels" -}}
app.kubernetes.io/name: status-page
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}
