# --- Locals ------------------------------------------------------------------
# Locals are named expressions: computed once, used everywhere. Unlike
# variables they cannot be overridden from outside, which is exactly what you
# want for something like a tag set that must be identical on every resource.

locals {
  tags = merge(
    {
      owner_email     = var.owner_email
      owner_name      = var.owner_name
      cflt_service    = var.cflt_service
      cflt_managed_by = var.cflt_managed_by
      cflt_managed_id = var.cflt_managed_id
      cflt_keep_until = var.cflt_keep_until

      Project   = var.name
      ManagedBy = "terraform"
    },
    var.extra_tags,
  )
}
