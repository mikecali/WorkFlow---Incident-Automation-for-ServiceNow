name: Optimized Version - Create ServiceNow Incident (Using Direct API)
description: Creates or closes ServiceNow incidents using LLM semantic analysis
enabled: true
tags:
  - servicenow
  - incident-management
  - llm-auto-resolve

consts:
  servicenow_url: "https://dev291312.service-now.com"
  servicenow_auth: "xxxxxxx-yyyyyyyyyyyyyyy="
  es_url: "https://demo-0b4ab0.es.us-east-2.aws.elastic-cloud.com"
  es_auth: "xxxxxxx-yyyyyyyyyyyyyyyzzzzzzzzzzzzzzzzzzz0=="

triggers:
  - type: alert

steps:

  - name: llm_assess_event
    type: http
    with:
      url: "{{ consts.es_url }}/_inference/completion/.anthropic-claude-3.7-sonnet-completion"
      method: POST
      headers:
        Content-Type: "application/json"
        Authorization: "ApiKey {{ consts.es_auth }}"
      body: |
        {
          "input": "You are an IT incident manager analyzing alert events from an automation platform. Determine if this alert is a NEW ERROR or a RECOVERY from a previous incident.\n\nAlert Status  : {{ event.alerts[0].kibana.alert.grouping.alert_status }}\nRecipe Name   : {{ event.alerts[0].kibana.alert.grouping.recipe_name }}\nError Type    : {{ event.alerts[0].kibana.alert.grouping.error_type }}\nError Message : {{ event.alerts[0].kibana.alert.grouping.error_message }}\nDescription   : {{ event.alerts[0].kibana.alert.grouping.error_description }}\nAlert ID      : {{ event.alerts[0].kibana.alert.grouping.alert_id }}\n\nRules:\n- recovered status OR message indicates restoration/success: is_recovery = true\n- fired status OR message indicates failure/error/timeout: is_recovery = false\n\nIMPORTANT: Return ONLY raw JSON. No markdown. No code blocks. No backticks. No explanation before or after. Your entire response must start with { and end with }.\n\n{\n  \"is_recovery\": true,\n  \"event_summary\": \"one sentence summary\",\n  \"resolution_summary\": \"one sentence for ServiceNow close notes\",\n  \"confidence\": 90,\n  \"reasoning\": \"brief explanation\"\n}"
        }

  - name: create_servicenow_incident
    type: http
    if: "event.alerts[0].kibana.alert.grouping.alert_status : fired"
    with:
      url: "{{ consts.servicenow_url }}/api/now/table/incident"
      method: POST
      headers:
        Content-Type: "application/json"
        Accept: "application/json"
        Authorization: "Basic {{ consts.servicenow_auth }}"
      body:
        short_description: "[{{ event.alerts[0].kibana.alert.grouping.error_type }}] {{ event.alerts[0].kibana.alert.grouping.recipe_name }} (Job: {{ event.alerts[0].kibana.alert.grouping.job_id }})"
        description: "AOF Recipe Error Detected | Recipe: {{ event.alerts[0].kibana.alert.grouping.recipe_id }} | Name: {{ event.alerts[0].kibana.alert.grouping.recipe_name }} | Job: {{ event.alerts[0].kibana.alert.grouping.job_id }} | Domain: {{ event.alerts[0].kibana.alert.grouping.recipe_domain }} | Time: {{ event.alerts[0].kibana.alert.grouping.timestamp }} | Error Type: {{ event.alerts[0].kibana.alert.grouping.error_type }} | Error: {{ event.alerts[0].kibana.alert.grouping.error_message }} | Desc: {{ event.alerts[0].kibana.alert.grouping.error_description }} | CI: {{ event.alerts[0].kibana.alert.grouping.servicenow_ci }} | LLM: {{ steps.llm_assess_event.output.data.completion[0].result }}"
        correlation_id: "AOF-{{ event.alerts[0].kibana.alert.grouping.recipe_id }}-{{ event.alerts[0].kibana.alert.grouping.job_id }}"
        severity: "{{ event.alerts[0].kibana.alert.grouping.severity_level }}"
        urgency: "{{ event.alerts[0].kibana.alert.grouping.severity_level }}"
        impact: "{{ event.alerts[0].kibana.alert.grouping.severity_level }}"
        category: "software"

  - name: find_open_incident
    type: http
    if: "event.alerts[0].kibana.alert.grouping.alert_status : recovered"
    with:
      url: "{{ consts.servicenow_url }}/api/now/table/incident?sysparm_query=correlation_id=AOF-{{ event.alerts[0].kibana.alert.grouping.recipe_id }}-{{ event.alerts[0].kibana.alert.grouping.job_id }}^active=true^stateNOT IN6,7&sysparm_limit=1&sysparm_display_value=false&sysparm_exclude_reference_link=true"
      method: GET
      headers:
        Content-Type: "application/json"
        Accept: "application/json"
        Authorization: "Basic {{ consts.servicenow_auth }}"

  - name: close_incident
    type: http
    if: "steps.find_open_incident.output.data.result[0].sys_id : *"
    with:
      url: "{{ consts.servicenow_url }}/api/now/table/incident/{{ steps.find_open_incident.output.data.result[0].sys_id }}"
      method: PATCH
      headers:
        Content-Type: "application/json"
        Accept: "application/json"
        Authorization: "Basic {{ consts.servicenow_auth }}"
      body:
        state: 6
        incident_state: 6
        resolved_at: "{{ event.alerts[0].kibana.alert.grouping.timestamp }}"
        close_code: "Solution provided"
        close_notes: "Auto-resolved by LLM Semantic Analysis | LLM: {{ steps.llm_assess_event.output.data.completion[0].result }} | Recovered at: {{ event.alerts[0].kibana.alert.grouping.timestamp }} | Alert ID: {{ event.alerts[0].kibana.alert.grouping.alert_id }}"
