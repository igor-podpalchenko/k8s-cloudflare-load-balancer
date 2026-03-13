package webhook

import (
	"context"
	"encoding/json"
	"strings"

	admissionv1 "k8s.io/api/admission/v1"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"
)

type ServiceMutator struct {
	LBClass string
}

func (m *ServiceMutator) Handle(_ context.Context, req admission.Request) admission.Response {
	if req.Operation != admissionv1.Create {
		return admission.Allowed("operation is not create")
	}

	svc := &corev1.Service{}
	if err := json.Unmarshal(req.Object.Raw, svc); err != nil {
		return admission.Errored(400, err)
	}
	if svc.Spec.Type != corev1.ServiceTypeLoadBalancer {
		return admission.Allowed("service is not LoadBalancer")
	}
	if svc.Spec.LoadBalancerClass != nil && strings.TrimSpace(*svc.Spec.LoadBalancerClass) != "" {
		return admission.Allowed("loadBalancerClass already set")
	}
	class := strings.TrimSpace(m.LBClass)
	if class == "" {
		return admission.Allowed("configured class is empty")
	}

	svc.Spec.LoadBalancerClass = &class
	mutated, err := json.Marshal(svc)
	if err != nil {
		return admission.Errored(500, err)
	}
	return admission.PatchResponseFromRaw(req.Object.Raw, mutated)
}
