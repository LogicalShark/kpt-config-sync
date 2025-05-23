// Copyright 2022 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package clusterconfig

import (
	"fmt"
	"testing"

	"github.com/google/go-cmp/cmp"
	"github.com/google/go-cmp/cmp/cmpopts"
	apiextensionsv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	apiextensionsv1beta1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1beta1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	v1 "kpt.dev/configsync/pkg/api/configmanagement/v1"
	"kpt.dev/configsync/pkg/core"
	"kpt.dev/configsync/pkg/core/k8sobjects"
	"kpt.dev/configsync/pkg/kinds"
	"kpt.dev/configsync/pkg/status"
	"kpt.dev/configsync/pkg/syncer/decode"
	"kpt.dev/configsync/pkg/testing/testerrors"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

func preserveUnknownFields(t *testing.T, preserved bool) core.MetaMutator {
	return func(o client.Object) {
		switch crd := o.(type) {
		case *apiextensionsv1beta1.CustomResourceDefinition:
			crd.Spec.PreserveUnknownFields = &preserved
		case *apiextensionsv1.CustomResourceDefinition:
			crd.Spec.PreserveUnknownFields = preserved
		default:
			t.Fatalf("not a v1beta1.CRD or v1.CRD: %T", o)
		}
	}
}

func TestGetCRDs(t *testing.T) {
	testCases := []struct {
		name string
		objs []client.Object
		want []*apiextensionsv1.CustomResourceDefinition
	}{
		{
			name: "No CRDs",
			want: []*apiextensionsv1.CustomResourceDefinition{},
		},
		{
			name: "v1Beta1 CRD",
			objs: []client.Object{
				k8sobjects.CRDV1beta1UnstructuredForGVK(kinds.Anvil(), apiextensionsv1.NamespaceScoped),
			},
			want: []*apiextensionsv1.CustomResourceDefinition{
				k8sobjects.CRDV1ObjectForGVK(kinds.Anvil(), apiextensionsv1.NamespaceScoped),
			},
		},
		{
			name: "v1 CRD",
			objs: []client.Object{
				k8sobjects.CRDV1UnstructuredForGVK(kinds.Anvil(), apiextensionsv1.NamespaceScoped),
			},
			want: []*apiextensionsv1.CustomResourceDefinition{
				k8sobjects.CRDV1ObjectForGVK(kinds.Anvil(), apiextensionsv1.NamespaceScoped,
					preserveUnknownFields(t, false)),
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			decoder := decode.NewGenericResourceDecoder(core.Scheme)
			cc := clusterConfig(tc.objs...)
			actual, err := GetCRDs(decoder, cc)

			if err != nil {
				t.Fatal(err)
			}

			opts := []cmp.Option{
				cmpopts.EquateEmpty(),
				cmpopts.IgnoreFields(apiextensionsv1.CustomResourceDefinition{}, "TypeMeta"),
			}
			if diff := cmp.Diff(tc.want, actual, opts...); diff != "" {
				t.Error(diff)
			}
		})
	}
}

const importToken = "abcde"

// clusterConfig generates a valid ClusterConfig to be put in AllConfigs given the set of hydrated
// cluster-scoped client.Objects.
func clusterConfig(objects ...client.Object) *v1.ClusterConfig {
	config := k8sobjects.ClusterConfigObject()
	config.Spec.Token = importToken
	for _, o := range objects {
		config.AddResource(o)
	}
	return config
}

func generateMalformedCRD(t *testing.T) *unstructured.Unstructured {
	u := k8sobjects.CRDV1beta1UnstructuredForGVK(kinds.Anvil(), apiextensionsv1.NamespaceScoped)

	// the `spec.group` field should be a string
	// set it to a bool to construct a malformed CRD
	if err := unstructured.SetNestedField(u.Object, false, "spec", "group"); err != nil {
		t.Fatalf("failed to set the generation field: %T", u)
	}
	return u
}

func TestToCRD(t *testing.T) {
	testCases := []struct {
		name    string
		obj     *unstructured.Unstructured
		wantErr status.Error
	}{
		{
			name:    "well-formed v1beta1 CRD",
			obj:     k8sobjects.CRDV1beta1UnstructuredForGVK(kinds.Anvil(), apiextensionsv1.NamespaceScoped),
			wantErr: nil,
		},
		{
			name:    "well-formed v1 CRD",
			obj:     k8sobjects.CRDV1UnstructuredForGVK(kinds.Anvil(), apiextensionsv1.NamespaceScoped),
			wantErr: nil,
		},
		{
			name: "mal-formed CRD",
			obj:  generateMalformedCRD(t),
			wantErr: MalformedCRDError(
				fmt.Errorf("unable to convert unstructured object to %v: %v",
					kinds.CustomResourceDefinition().WithVersion("v1beta1"),
					fmt.Errorf("unrecognized type: string")),
				generateMalformedCRD(t)),
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := ToCRD(tc.obj, core.Scheme)
			testerrors.AssertEqual(t, tc.wantErr, err)
		})
	}
}
