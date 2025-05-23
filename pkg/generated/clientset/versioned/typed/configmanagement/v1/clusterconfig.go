// Code generated by client-gen. DO NOT EDIT.

package v1

import (
	context "context"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	types "k8s.io/apimachinery/pkg/types"
	watch "k8s.io/apimachinery/pkg/watch"
	gentype "k8s.io/client-go/gentype"
	configmanagementv1 "kpt.dev/configsync/pkg/api/configmanagement/v1"
	scheme "kpt.dev/configsync/pkg/generated/clientset/versioned/scheme"
)

// ClusterConfigsGetter has a method to return a ClusterConfigInterface.
// A group's client should implement this interface.
type ClusterConfigsGetter interface {
	ClusterConfigs() ClusterConfigInterface
}

// ClusterConfigInterface has methods to work with ClusterConfig resources.
type ClusterConfigInterface interface {
	Create(ctx context.Context, clusterConfig *configmanagementv1.ClusterConfig, opts metav1.CreateOptions) (*configmanagementv1.ClusterConfig, error)
	Update(ctx context.Context, clusterConfig *configmanagementv1.ClusterConfig, opts metav1.UpdateOptions) (*configmanagementv1.ClusterConfig, error)
	// Add a +genclient:noStatus comment above the type to avoid generating UpdateStatus().
	UpdateStatus(ctx context.Context, clusterConfig *configmanagementv1.ClusterConfig, opts metav1.UpdateOptions) (*configmanagementv1.ClusterConfig, error)
	Delete(ctx context.Context, name string, opts metav1.DeleteOptions) error
	DeleteCollection(ctx context.Context, opts metav1.DeleteOptions, listOpts metav1.ListOptions) error
	Get(ctx context.Context, name string, opts metav1.GetOptions) (*configmanagementv1.ClusterConfig, error)
	List(ctx context.Context, opts metav1.ListOptions) (*configmanagementv1.ClusterConfigList, error)
	Watch(ctx context.Context, opts metav1.ListOptions) (watch.Interface, error)
	Patch(ctx context.Context, name string, pt types.PatchType, data []byte, opts metav1.PatchOptions, subresources ...string) (result *configmanagementv1.ClusterConfig, err error)
	ClusterConfigExpansion
}

// clusterConfigs implements ClusterConfigInterface
type clusterConfigs struct {
	*gentype.ClientWithList[*configmanagementv1.ClusterConfig, *configmanagementv1.ClusterConfigList]
}

// newClusterConfigs returns a ClusterConfigs
func newClusterConfigs(c *ConfigmanagementV1Client) *clusterConfigs {
	return &clusterConfigs{
		gentype.NewClientWithList[*configmanagementv1.ClusterConfig, *configmanagementv1.ClusterConfigList](
			"clusterconfigs",
			c.RESTClient(),
			scheme.ParameterCodec,
			"",
			func() *configmanagementv1.ClusterConfig { return &configmanagementv1.ClusterConfig{} },
			func() *configmanagementv1.ClusterConfigList { return &configmanagementv1.ClusterConfigList{} },
		),
	}
}
