# Illinois Data Bank Integration with Illinois Experts

Illinois Data Bank serves information about datasets in Illinois authored by members of the University of Illinois at Urbana-Champaign.

Illinois Data Bank uses information from the PURE API to get relevant information to use in generating a usable data document.

The Illinois Experts system consumes the data document using the endpoint `/illinois_experts.xml`

## Configuration

Illinois Experts configuration follows legacy databank behavior:

- Primary source: `Rails.application.credentials[:illinois_experts]`
- Fallback source: environment variables

Supported keys:

- `key` (`ILLINOIS_EXPERTS_KEY`)
- `endpoint` (`ILLINOIS_EXPERTS_ENDPOINT`)
- `org_id` (`ILLINOIS_EXPERTS_ORG_ID`)
- `publisher_id` (`ILLINOIS_EXPERTS_PUBLISHER_ID`)
- `illinois_external_org_id` (`ILLINOIS_EXPERTS_EXTERNAL_ORG_ID`)

## References

- **Path:** https://databank.illinois.edu/illinois_experts.xml
- **Service Site:** https://experts.illinois.edu/
- **About:** https://publish.illinois.edu/experts-help/
- **PURE API:** https://experts.illinois.edu/ws/api/524/api-docs/index.html#!/persons/listPersonProjects
