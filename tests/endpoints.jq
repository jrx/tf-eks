# jq -es -f tests/endpoints.jq <output from terraform test -json -verbose>
# The upstream module does not export the endpoint flags. Check the actual EKS resource.
def expected: {
  private_defaults: [],
  laptop_admin: ["203.0.113.7/32"],
  network_only: ["203.0.113.0/24"],
  identity_only: []
};
[.[] | select(.type == "test_plan") | .["@testrun"] as $run
 | select(expected | has($run))
 | .test_plan.resource_changes[] | select(.address == "module.eks.aws_eks_cluster.this[0]")
 | .change.after.vpc_config[0] as $vpc
 | {run: $run, ok: ($vpc.endpoint_private_access == true
     and $vpc.endpoint_public_access == (expected[$run] != [])
     and (expected[$run] == [] or $vpc.public_access_cidrs == expected[$run]))}]
| (map(.run) | sort) == (expected | keys) and all(.[]; .ok)
