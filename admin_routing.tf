# La routing table del pannello amministrativo.
#
# Vive nell'account del pannello e non su `tenants`: la piattaforma sta su quattro
# account, quindi il control plane non può leggere la tabella tenant di un altro; e
# quella tabella la legge l'authorizer di powerflow a ogni richiesta, dove una PutItem
# del pannello cancellerebbe attributi che servono all'autorizzazione.
#
# Documentato in admin-portal-api/docs/adr/0001-instradamento-dei-tenant.md.

locals {
  # Deve combaciare con domain.DefaultRoutingSlug nel portale. Prefissato con
  # underscore perché nessuno slug può collidere: il pattern degli slug lo rifiuta.
  admin_routing_default_slug = "_default"

  admin_routing_rows = var.admin_routing == null ? {} : merge(
    { (local.admin_routing_default_slug) = var.admin_routing.defaults },
    var.admin_routing.tenants,
  )
}

resource "aws_dynamodb_table_item" "admin_routing" {
  for_each = local.admin_routing_rows

  table_name = module.dynamodb_tables[var.admin_routing.table].dynamodb_table_id
  # Dalla dichiarazione e non dal modulo, che non lo espone come output.
  hash_key = var.dynamodb_tables[var.admin_routing.table].hash_key

  # Una mappa vuota è legale su DynamoDB (a differenza di un set vuoto), quindi un
  # tenant che eredita tutto dal default si scrive `{}` senza casi speciali.
  item = jsonencode({
    tenant = { S = each.key }
    services = { M = {
      for name, endpoint in each.value : name => { M = merge(
        { base_url = { S = endpoint.base_url } },
        endpoint.api_key_secret_id == null ? {} : {
          api_key_secret_id = { S = endpoint.api_key_secret_id }
        },
      ) }
    } }
  })
}
