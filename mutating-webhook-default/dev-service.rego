package system
import data.kubernetes.admission

# Entry point to the policy. This is queried by the Kubernetes apiserver.
main = {
    "apiVersion": "admission.k8s.io/v1",
    "kind": "AdmissionReview",
    "response": response,
}

# If no other responses are defined, allow the request.
default response = {
    "allowed": true,
    "uid": 0
}

response = {
    "allowed": false,
    "uid": input.request.uid,
    "status": {
        "reason": reason
    }
} {
    reason = concat(", ", admission.deny)
    reason != ""
}

# Mutate the request if any there are any patches.
response = {
    "allowed": true,
    "uid": input.request.uid,
    "patchType": "JSONPatch",
    "patch": base64url.encode(json.marshal(patches)),
} {
    patches := [p | p := patch[_][_]] # iterate over all patches and generate a flattened array
    count(patches) > 0
}

# Note: patch generates a _set_ of arrays. The ordering of the set is not defined.
# If you need to define ordering across patches, generate them inside the same rule.
patch[[
    {
        "op": "add",
        "path": "/metadata/annotations/service.beta.kubernetes.io~1kinx-load-balancer-backend-protocol",
        "value": "tcp",
    }
]] {

    # Only apply mutations to objects in create/update operations (not
    # delete/connect operations.)
    
    need_patch
    not need_annotations
    need_lb_annotations
    # If the resource has the "test-mutation" annotation key, the patch will be
    # generated and applied to the resource.   
    
}
patch[[
    {
        "op": "add",
        "path": "/metadata/annotations",
        "value": {"service.beta.kubernetes.io/kinx-load-balancer-backend-protocol" : "tcp"},
    }
]] {
    need_patch
    need_annotations
}

need_patch { 
    is_create_or_update
    is_target_service
    need_annotations    
}
need_patch {
    is_create_or_update
    is_target_service
    need_lb_annotations
}

is_create_or_update { is_create }
is_create_or_update { is_update }
is_create { input.request.operation == "CREATE" }
is_update { input.request.operation == "UPDATE" }

is_target_service {
    is_service
    is_loadbalancer 
}

is_service { input.request.object.kind == "Service" }
is_loadbalancer { input.request.object.spec.type == "LoadBalancer" }

need_annotations { object.get(input.request.object.metadata,"annotations",null) == null }
need_lb_annotations { 
    not need_annotations
    object.get(input.request.object.metadata.annotations,"service.beta.kubernetes.io/kinx-load-balancer-backend-protocol",null) == null 
}
