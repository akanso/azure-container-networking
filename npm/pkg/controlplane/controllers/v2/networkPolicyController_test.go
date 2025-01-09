// Copyright 2018 Microsoft. All rights reserved.
// MIT License
package controllers

import (
	"fmt"
	"strconv"
	"testing"

	"github.com/Azure/azure-container-networking/npm/metrics"
	"github.com/Azure/azure-container-networking/npm/metrics/promutil"
	"github.com/Azure/azure-container-networking/npm/pkg/dataplane"
	dpmocks "github.com/Azure/azure-container-networking/npm/pkg/dataplane/mocks"
	"github.com/Azure/azure-container-networking/npm/util"
	gomock "github.com/golang/mock/gomock"
	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/util/intstr"
	kubeinformers "k8s.io/client-go/informers"
	k8sfake "k8s.io/client-go/kubernetes/fake"
	"k8s.io/client-go/tools/cache"
)

type netPolFixture struct {
	t *testing.T

	// Objects to put in the store.
	netPolLister []*networkingv1.NetworkPolicy
	// Objects from here preloaded into NewSimpleFake.
	kubeobjects []runtime.Object

	netPolController *NetworkPolicyController

	kubeInformer kubeinformers.SharedInformerFactory
}

func newNetPolFixture(t *testing.T) *netPolFixture {
	f := &netPolFixture{
		t:            t,
		netPolLister: []*networkingv1.NetworkPolicy{},
		kubeobjects:  []runtime.Object{},
	}
	return f
}

func (f *netPolFixture) newNetPolController(_ chan struct{}, dp dataplane.GenericDataplane, npmLiteToggle bool) {
	kubeclient := k8sfake.NewSimpleClientset(f.kubeobjects...)
	f.kubeInformer = kubeinformers.NewSharedInformerFactory(kubeclient, noResyncPeriodFunc())

	f.netPolController = NewNetworkPolicyController(f.kubeInformer.Networking().V1().NetworkPolicies(), dp, npmLiteToggle)

	for _, netPol := range f.netPolLister {
		err := f.kubeInformer.Networking().V1().NetworkPolicies().Informer().GetIndexer().Add(netPol)
		if err != nil {
			f.t.Errorf("Failed to add network policy %s to shared informer cache: %v", netPol.Name, err)
		}
	}

	metrics.ReinitializeAll()

	// Do not start informer to avoid unnecessary event triggers
	// (TODO): Leave stopCh and below commented code to enhance UTs to even check event triggers as well later if possible
	// f.kubeInformer.Start(stopCh)
}

// (TODO): make createNetPol flexible
func createNetPol() *networkingv1.NetworkPolicy {
	tcp := corev1.ProtocolTCP
	port8000 := intstr.FromInt(8000)
	return &networkingv1.NetworkPolicy{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "allow-ingress",
			Namespace: "test-nwpolicy",
		},
		Spec: networkingv1.NetworkPolicySpec{
			PolicyTypes: []networkingv1.PolicyType{
				networkingv1.PolicyTypeIngress,
				networkingv1.PolicyTypeEgress,
			},

			Ingress: []networkingv1.NetworkPolicyIngressRule{
				{
					From: []networkingv1.NetworkPolicyPeer{
						{
							PodSelector: &metav1.LabelSelector{
								MatchLabels: map[string]string{"app": "test"},
							},
						},
						{
							IPBlock: &networkingv1.IPBlock{
								CIDR: "0.0.0.0/0",
							},
						},
					},
					Ports: []networkingv1.NetworkPolicyPort{{
						Protocol: &tcp,
						Port:     &port8000,
					}},
				},
			},
			Egress: []networkingv1.NetworkPolicyEgressRule{
				{
					To: []networkingv1.NetworkPolicyPeer{{
						PodSelector: &metav1.LabelSelector{
							MatchLabels: map[string]string{"app": "test"},
						},
					}},
					Ports: []networkingv1.NetworkPolicyPort{{
						Protocol: &tcp,
						Port:     &intstr.IntOrString{StrVal: "8000"}, // namedPort
					}},
				},
			},
		},
	}
}

func createNetPolNpmLite() *networkingv1.NetworkPolicy {
	tcp := corev1.ProtocolTCP
	port8000 := intstr.FromInt(8000)
	return &networkingv1.NetworkPolicy{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "allow-ingress",
			Namespace: "test-nwpolicy",
		},
		Spec: networkingv1.NetworkPolicySpec{
			PolicyTypes: []networkingv1.PolicyType{
				networkingv1.PolicyTypeIngress,
				networkingv1.PolicyTypeEgress,
			},

			Ingress: []networkingv1.NetworkPolicyIngressRule{
				{
					From: []networkingv1.NetworkPolicyPeer{
						{
							IPBlock: &networkingv1.IPBlock{
								CIDR: "0.0.0.0/0",
							},
						},
					},
					Ports: []networkingv1.NetworkPolicyPort{{
						Protocol: &tcp,
						Port:     &port8000,
					}},
				},
			},
			Egress: []networkingv1.NetworkPolicyEgressRule{
				{
					To: []networkingv1.NetworkPolicyPeer{
						{
							IPBlock: &networkingv1.IPBlock{
								CIDR: "0.0.0.0/0",
							},
						},
					},
					Ports: []networkingv1.NetworkPolicyPort{{
						Protocol: &tcp,
						Port:     &intstr.IntOrString{IntVal: 8000}, // namedPort
					}},
				},
			},
		},
	}
}

func addNetPol(f *netPolFixture, netPolObj *networkingv1.NetworkPolicy) {
	// simulate "network policy" add event and add network policy object to sharedInformer cache
	f.netPolController.addNetworkPolicy(netPolObj)

	if f.netPolController.workqueue.Len() == 0 {
		return
	}

	f.netPolController.processNextWorkItem()
}

func addAndDeleteNetPol(t *testing.T, f *netPolFixture, netPolObj *networkingv1.NetworkPolicy, isDeletedFinalStateUnknownObject IsDeletedFinalStateUnknownObject) {
	addNetPol(f, netPolObj)
	t.Logf("Complete adding network policy event")
	deleteNetPol(t, f, netPolObj, isDeletedFinalStateUnknownObject)
}

func deleteNetPol(t *testing.T, f *netPolFixture, netPolObj *networkingv1.NetworkPolicy, isDeletedFinalStateUnknownObject IsDeletedFinalStateUnknownObject) {
	// simulate network policy deletion event and delete network policy object from sharedInformer cache
	err := f.kubeInformer.Networking().V1().NetworkPolicies().Informer().GetIndexer().Delete(netPolObj)
	if err != nil {
		f.t.Errorf("Failed to delete network policy %s to shared informer cache: %v", netPolObj.Name, err)
	}
	if isDeletedFinalStateUnknownObject {
		netPolKey := getKey(netPolObj, t)
		tombstone := cache.DeletedFinalStateUnknown{
			Key: netPolKey,
			Obj: netPolObj,
		}
		f.netPolController.deleteNetworkPolicy(tombstone)
	} else {
		f.netPolController.deleteNetworkPolicy(netPolObj)
	}

	if f.netPolController.workqueue.Len() == 0 {
		return
	}

	f.netPolController.processNextWorkItem()
}

func addAndUpdateNetPol(t *testing.T, f *netPolFixture, oldNetPolObj, newNetPolObj *networkingv1.NetworkPolicy) {
	addNetPol(f, oldNetPolObj)
	t.Logf("Complete adding network policy event")
	updateNetPol(t, f, oldNetPolObj, newNetPolObj)
}

func updateNetPol(t *testing.T, f *netPolFixture, oldNetPolObj, newNetPolObj *networkingv1.NetworkPolicy) {
	// simulate network policy update event and update the network policy to shared informer's cache
	err := f.kubeInformer.Networking().V1().NetworkPolicies().Informer().GetIndexer().Update(newNetPolObj)
	if err != nil {
		f.t.Errorf("Failed to update network policy %s to shared informer cache: %v", newNetPolObj.Name, err)
	}
	f.netPolController.updateNetworkPolicy(oldNetPolObj, newNetPolObj)

	if f.netPolController.workqueue.Len() == 0 {
		return
	}

	f.netPolController.processNextWorkItem()
}

type expectedNetPolValues struct {
	expectedLenOfRawNpMap  int
	expectedLenOfWorkQueue int
	netPolPromVals
}

type netPolPromVals struct {
	expectedNumPolicies     int
	expectedAddExecCount    int
	expectedUpdateExecCount int
	expectedDeleteExecCount int
}

// for local testing, prepend the following to your go test command: sudo -E env 'PATH=$PATH'
func (p *netPolPromVals) testPrometheusMetrics(t *testing.T) {
	numPolicies, err := metrics.GetNumPolicies()
	promutil.NotifyIfErrors(t, err)
	if numPolicies != p.expectedNumPolicies {
		require.FailNowf(t, "", "Number of policies didn't register correctly in Prometheus. Expected %d. Got %d.", p.expectedNumPolicies, numPolicies)
	}

	addExecCount, err := metrics.GetControllerPolicyExecCount(metrics.CreateOp, false)
	promutil.NotifyIfErrors(t, err)
	require.Equal(t, p.expectedAddExecCount, addExecCount, "Count for add execution time didn't register correctly in Prometheus")

	addErrorExecCount, err := metrics.GetControllerPolicyExecCount(metrics.CreateOp, true)
	promutil.NotifyIfErrors(t, err)
	require.Equal(t, 0, addErrorExecCount, "Count for add error execution time should be 0")

	updateExecCount, err := metrics.GetControllerPolicyExecCount(metrics.UpdateOp, false)
	promutil.NotifyIfErrors(t, err)
	require.Equal(t, p.expectedUpdateExecCount, updateExecCount, "Count for update execution time didn't register correctly in Prometheus")

	updateErrorExecCount, err := metrics.GetControllerPolicyExecCount(metrics.UpdateOp, true)
	promutil.NotifyIfErrors(t, err)
	require.Equal(t, 0, updateErrorExecCount, "Count for update error execution time should be 0")

	deleteExecCount, err := metrics.GetControllerPolicyExecCount(metrics.DeleteOp, false)
	promutil.NotifyIfErrors(t, err)
	require.Equal(t, p.expectedDeleteExecCount, deleteExecCount, "Count for delete execution time didn't register correctly in Prometheus")

	deleteErrorExecCount, err := metrics.GetControllerPolicyExecCount(metrics.DeleteOp, true)
	promutil.NotifyIfErrors(t, err)
	require.Equal(t, 0, deleteErrorExecCount, "Count for delete error execution time should be 0")
}

func checkNetPolTestResult(testName string, f *netPolFixture, testCases []expectedNetPolValues) {
	for _, test := range testCases {
		if got := f.netPolController.LengthOfRawNpMap(); got != test.expectedLenOfRawNpMap {
			f.t.Errorf("Test: %s, Raw NetPol Map length = %d, want %d", testName, got, test.expectedLenOfRawNpMap)
		}

		if got := f.netPolController.workqueue.Len(); got != test.expectedLenOfWorkQueue {
			f.t.Errorf("Test: %s, Workqueue length = %d, want %d", testName, got, test.expectedLenOfWorkQueue)
		}

		test.netPolPromVals.testPrometheusMetrics(f.t)
	}
}

func TestAddMultipleNetworkPolicies(t *testing.T) {
	netPolObj1 := createNetPol()

	// deep copy netPolObj1 and change namespace, name, and porttype (to namedPort) since current createNetPol is not flexble.
	netPolObj2 := netPolObj1.DeepCopy()
	netPolObj2.Namespace = fmt.Sprintf("%s-new", netPolObj1.Namespace)
	netPolObj2.Name = fmt.Sprintf("%s-new", netPolObj1.Name)
	// namedPort
	netPolObj2.Spec.Ingress[0].Ports[0].Port = &intstr.IntOrString{StrVal: netPolObj2.Name}

	f := newNetPolFixture(t)
	f.netPolLister = append(f.netPolLister, netPolObj1, netPolObj2)
	f.kubeobjects = append(f.kubeobjects, netPolObj1, netPolObj2)
	stopCh := make(chan struct{})
	defer close(stopCh)

	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	dp := dpmocks.NewMockGenericDataplane(ctrl)
	f.newNetPolController(stopCh, dp, false)
	var testCases []expectedNetPolValues

	if util.IsWindowsDP() {
		dp.EXPECT().UpdatePolicy(gomock.Any()).Times(0)
		// named ports are not allowed on windows
		testCases = []expectedNetPolValues{
			{0, 0, netPolPromVals{0, 0, 0, 0}},
		}
	} else {
		dp.EXPECT().UpdatePolicy(gomock.Any()).Times(2)

		testCases = []expectedNetPolValues{
			{2, 0, netPolPromVals{2, 2, 0, 0}},
		}
	}
	addNetPol(f, netPolObj1)
	addNetPol(f, netPolObj2)

	// already exists (will be a no-op)
	addNetPol(f, netPolObj1)

	checkNetPolTestResult("TestAddMultipleNetPols", f, testCases)
}

func TestAddNetworkPolicy(t *testing.T) {
	netPolObj := createNetPol()

	f := newNetPolFixture(t)
	f.netPolLister = append(f.netPolLister, netPolObj)
	f.kubeobjects = append(f.kubeobjects, netPolObj)
	stopCh := make(chan struct{})
	defer close(stopCh)
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	dp := dpmocks.NewMockGenericDataplane(ctrl)
	f.newNetPolController(stopCh, dp, false)

	var testCases []expectedNetPolValues

	if util.IsWindowsDP() {
		dp.EXPECT().UpdatePolicy(gomock.Any()).Times(0)
		// named ports are not allowed on windows
		testCases = []expectedNetPolValues{
			{0, 0, netPolPromVals{0, 0, 0, 0}},
		}
	} else {
		dp.EXPECT().UpdatePolicy(gomock.Any()).Times(1)

		testCases = []expectedNetPolValues{
			{1, 0, netPolPromVals{1, 1, 0, 0}},
		}
	}
	addNetPol(f, netPolObj)

	checkNetPolTestResult("TestAddNetPol", f, testCases)
}

func TestAddNetworkPolicyWithNumericPort(t *testing.T) {
	netPolObj := createNetPol()
	netPolObj.Spec.Egress[0].Ports[0].Port = &intstr.IntOrString{IntVal: 8000}
	f := newNetPolFixture(t)
	f.netPolLister = append(f.netPolLister, netPolObj)
	f.kubeobjects = append(f.kubeobjects, netPolObj)
	stopCh := make(chan struct{})
	defer close(stopCh)
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	dp := dpmocks.NewMockGenericDataplane(ctrl)
	f.newNetPolController(stopCh, dp, false)

	var testCases []expectedNetPolValues

	dp.EXPECT().UpdatePolicy(gomock.Any()).Times(1)

	addNetPol(f, netPolObj)
	testCases = []expectedNetPolValues{
		{1, 0, netPolPromVals{1, 1, 0, 0}},
	}

	checkNetPolTestResult("TestAddNetPol", f, testCases)
}

func TestAddNetworkPolicyWithNPMLite_Failure(t *testing.T) {
	netPolObj := createNetPol()

	f := newNetPolFixture(t)
	f.netPolLister = append(f.netPolLister, netPolObj)
	f.kubeobjects = append(f.kubeobjects, netPolObj)
	stopCh := make(chan struct{})
	defer close(stopCh)
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	dp := dpmocks.NewMockGenericDataplane(ctrl)
	f.newNetPolController(stopCh, dp, true)

	dp.EXPECT().UpdatePolicy(gomock.Any()).Times(0)

	addNetPol(f, netPolObj)
	testCases := []expectedNetPolValues{
		{0, 0, netPolPromVals{0, 0, 0, 0}},
	}

	checkNetPolTestResult("TestAddNetPol", f, testCases)
}

func TestAddNetworkPolicyWithNPMLite(t *testing.T) {
	netPolObj := createNetPolNpmLite()

	f := newNetPolFixture(t)
	f.netPolLister = append(f.netPolLister, netPolObj)
	f.kubeobjects = append(f.kubeobjects, netPolObj)
	stopCh := make(chan struct{})
	defer close(stopCh)
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	dp := dpmocks.NewMockGenericDataplane(ctrl)
	f.newNetPolController(stopCh, dp, true)

	dp.EXPECT().UpdatePolicy(gomock.Any()).Times(1)

	addNetPol(f, netPolObj)
	testCases := []expectedNetPolValues{
		{1, 0, netPolPromVals{1, 1, 0, 0}},
	}

	checkNetPolTestResult("TestAddNetPol", f, testCases)
}

func TestDeleteNetworkPolicy(t *testing.T) {
	netPolObj := createNetPol()

	f := newNetPolFixture(t)
	f.netPolLister = append(f.netPolLister, netPolObj)
	f.kubeobjects = append(f.kubeobjects, netPolObj)
	stopCh := make(chan struct{})
	defer close(stopCh)
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	dp := dpmocks.NewMockGenericDataplane(ctrl)
	f.newNetPolController(stopCh, dp, false)

	var testCases []expectedNetPolValues

	if util.IsWindowsDP() {
		dp.EXPECT().UpdatePolicy(gomock.Any()).Times(0)
		dp.EXPECT().RemovePolicy(gomock.Any()).Times(0)

		testCases = []expectedNetPolValues{
			{0, 0, netPolPromVals{0, 0, 0, 0}},
		}
	} else {
		dp.EXPECT().UpdatePolicy(gomock.Any()).Times(1)
		dp.EXPECT().RemovePolicy(gomock.Any()).Times(1)

		testCases = []expectedNetPolValues{
			{0, 0, netPolPromVals{0, 1, 0, 1}},
		}
	}
	addAndDeleteNetPol(t, f, netPolObj, DeletedFinalStateknownObject)
	checkNetPolTestResult("TestDelNetPol", f, testCases)
}

func TestDeleteNetworkPolicyWithTombstone(t *testing.T) {
	netPolObj := createNetPol()

	f := newNetPolFixture(t)
	f.netPolLister = append(f.netPolLister, netPolObj)
	f.kubeobjects = append(f.kubeobjects, netPolObj)
	stopCh := make(chan struct{})
	defer close(stopCh)
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	dp := dpmocks.NewMockGenericDataplane(ctrl)
	f.newNetPolController(stopCh, dp, false)

	netPolKey := getKey(netPolObj, t)
	tombstone := cache.DeletedFinalStateUnknown{
		Key: netPolKey,
		Obj: netPolObj,
	}

	f.netPolController.deleteNetworkPolicy(tombstone)
	testCases := []expectedNetPolValues{
		{0, 1, netPolPromVals{0, 0, 0, 0}},
	}
	checkNetPolTestResult("TestDeleteNetworkPolicyWithTombstone", f, testCases)
}

func TestDeleteNetworkPolicyWithTombstoneAfterAddingNetworkPolicy(t *testing.T) {
	netPolObj := createNetPol()

	f := newNetPolFixture(t)
	f.netPolLister = append(f.netPolLister, netPolObj)
	f.kubeobjects = append(f.kubeobjects, netPolObj)
	stopCh := make(chan struct{})
	defer close(stopCh)
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	dp := dpmocks.NewMockGenericDataplane(ctrl)
	f.newNetPolController(stopCh, dp, false)

	var testCases []expectedNetPolValues

	if util.IsWindowsDP() {
		dp.EXPECT().UpdatePolicy(gomock.Any()).Times(0)
		dp.EXPECT().RemovePolicy(gomock.Any()).Times(0)

		testCases = []expectedNetPolValues{
			{0, 0, netPolPromVals{0, 0, 0, 0}},
		}
	} else {
		dp.EXPECT().UpdatePolicy(gomock.Any()).Times(1)
		dp.EXPECT().RemovePolicy(gomock.Any()).Times(1)

		testCases = []expectedNetPolValues{
			{0, 0, netPolPromVals{0, 1, 0, 1}},
		}
	}
	addAndDeleteNetPol(t, f, netPolObj, DeletedFinalStateUnknownObject)

	checkNetPolTestResult("TestDeleteNetworkPolicyWithTombstoneAfterAddingNetworkPolicy", f, testCases)
}

// this unit test is for the case where states of network policy are changed, but network policy controller does not need to reconcile.
// Check it with expectedEnqueueEventIntoWorkQueue variable.
func TestUpdateNetworkPolicy(t *testing.T) {
	oldNetPolObj := createNetPol()

	f := newNetPolFixture(t)
	f.netPolLister = append(f.netPolLister, oldNetPolObj)
	f.kubeobjects = append(f.kubeobjects, oldNetPolObj)
	stopCh := make(chan struct{})
	defer close(stopCh)
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	dp := dpmocks.NewMockGenericDataplane(ctrl)
	f.newNetPolController(stopCh, dp, false)

	newNetPolObj := oldNetPolObj.DeepCopy()
	// oldNetPolObj.ResourceVersion value is "0"
	newRV, _ := strconv.Atoi(oldNetPolObj.ResourceVersion)
	newNetPolObj.ResourceVersion = fmt.Sprintf("%d", newRV+1)
	var testCases []expectedNetPolValues

	if util.IsWindowsDP() {
		dp.EXPECT().UpdatePolicy(gomock.Any()).Times(0)

		testCases = []expectedNetPolValues{
			{0, 0, netPolPromVals{0, 0, 0, 0}},
		}
	} else {
		dp.EXPECT().UpdatePolicy(gomock.Any()).Times(1)

		testCases = []expectedNetPolValues{
			{1, 0, netPolPromVals{1, 1, 0, 0}},
		}
	}
	addAndUpdateNetPol(t, f, oldNetPolObj, newNetPolObj)

	checkNetPolTestResult("TestUpdateNetPol", f, testCases)
}

func TestLabelUpdateNetworkPolicy(t *testing.T) {
	oldNetPolObj := createNetPol()

	f := newNetPolFixture(t)
	f.netPolLister = append(f.netPolLister, oldNetPolObj)
	f.kubeobjects = append(f.kubeobjects, oldNetPolObj)
	stopCh := make(chan struct{})
	defer close(stopCh)
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	dp := dpmocks.NewMockGenericDataplane(ctrl)
	f.newNetPolController(stopCh, dp, false)

	newNetPolObj := oldNetPolObj.DeepCopy()
	// update podSelctor in a new network policy field
	newNetPolObj.Spec.PodSelector = metav1.LabelSelector{
		MatchLabels: map[string]string{
			"app": "test",
			"new": "test",
		},
	}
	// oldNetPolObj.ResourceVersion value is "0"
	newRV, _ := strconv.Atoi(oldNetPolObj.ResourceVersion)
	newNetPolObj.ResourceVersion = fmt.Sprintf("%d", newRV+1)

	var testCases []expectedNetPolValues

	if util.IsWindowsDP() {
		dp.EXPECT().UpdatePolicy(gomock.Any()).Times(0)

		testCases = []expectedNetPolValues{
			{0, 0, netPolPromVals{0, 0, 0, 0}},
		}
	} else {
		dp.EXPECT().UpdatePolicy(gomock.Any()).Times(2)

		testCases = []expectedNetPolValues{
			{1, 0, netPolPromVals{1, 1, 1, 0}},
		}
	}
	addAndUpdateNetPol(t, f, oldNetPolObj, newNetPolObj)

	checkNetPolTestResult("TestUpdateNetPol", f, testCases)
}

func TestCountsAddAndDeleteNetPol(t *testing.T) {
	tests := []struct {
		name string
		// network policy to add
		netPolSpec     *networkingv1.NetworkPolicySpec
		cidrCount      int
		namedPortCount int
	}{
		{
			name: "no-cidr-namedPort",
			netPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
					networkingv1.PolicyTypeEgress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						From: []networkingv1.NetworkPolicyPeer{
							{
								PodSelector: &metav1.LabelSelector{
									MatchLabels: map[string]string{"app": "test"},
								},
							},
						},
						Ports: []networkingv1.NetworkPolicyPort{
							{
								Port: &intstr.IntOrString{IntVal: 8000},
							},
						},
					},
				},
				Egress: []networkingv1.NetworkPolicyEgressRule{
					{
						To: []networkingv1.NetworkPolicyPeer{
							{
								PodSelector: &metav1.LabelSelector{
									MatchLabels: map[string]string{"app": "test"},
								},
							},
						},
						Ports: []networkingv1.NetworkPolicyPort{
							{
								Port: &intstr.IntOrString{IntVal: 8000},
							},
						},
					},
				},
			},
		},
		{
			name: "cidr-ingress",
			netPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						From: []networkingv1.NetworkPolicyPeer{
							{
								IPBlock: &networkingv1.IPBlock{
									CIDR: "0.0.0.0/0",
								},
							},
						},
					},
				},
			},
			cidrCount: 1,
		},
		{
			name: "cidr-egress",
			netPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeEgress,
				},
				Egress: []networkingv1.NetworkPolicyEgressRule{
					{
						To: []networkingv1.NetworkPolicyPeer{
							{
								IPBlock: &networkingv1.IPBlock{
									CIDR: "0.0.0.0/0",
								},
							},
						},
					},
				},
			},
			cidrCount: 1,
		},
		{
			name: "namedPort-ingress",
			netPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						Ports: []networkingv1.NetworkPolicyPort{
							{
								Port: &intstr.IntOrString{StrVal: "abc"},
							},
						},
					},
				},
			},
			namedPortCount: 1,
		},
		{
			name: "namedPort-egress",
			netPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeEgress,
				},
				Egress: []networkingv1.NetworkPolicyEgressRule{
					{
						Ports: []networkingv1.NetworkPolicyPort{
							{
								Port: &intstr.IntOrString{StrVal: "abc"},
							},
						},
					},
				},
			},
			namedPortCount: 1,
		},
		{
			name: "cidr-and-namedPort",
			netPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						From: []networkingv1.NetworkPolicyPeer{
							{
								IPBlock: &networkingv1.IPBlock{
									CIDR: "0.0.0.0/0",
								},
							},
						},
						Ports: []networkingv1.NetworkPolicyPort{
							{
								Port: &intstr.IntOrString{StrVal: "abc"},
							},
						},
					},
				},
			},
			cidrCount:      1,
			namedPortCount: 1,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			f := newNetPolFixture(t)
			netPolObj := createNetPol()
			netPolObj.Spec = *tt.netPolSpec
			f.netPolLister = append(f.netPolLister, netPolObj)
			f.kubeobjects = append(f.kubeobjects, netPolObj)
			stopCh := make(chan struct{})
			defer close(stopCh)
			ctrl := gomock.NewController(t)
			defer ctrl.Finish()

			dp := dpmocks.NewMockGenericDataplane(ctrl)
			f.newNetPolController(stopCh, dp, false)

			dp.EXPECT().UpdatePolicy(gomock.Any()).Times(1)
			dp.EXPECT().RemovePolicy(gomock.Any()).Times(1)

			addNetPol(f, netPolObj)
			testCases := []expectedNetPolValues{
				{1, 0, netPolPromVals{1, 1, 0, 0}},
			}
			checkNetPolTestResult("TestCountsCreateNetPol", f, testCases)
			require.Equal(t, tt.cidrCount, metrics.GetCidrNetPols())
			require.Equal(t, tt.namedPortCount, metrics.GetNamedPortNetPols())

			deleteNetPol(t, f, netPolObj, DeletedFinalStateknownObject)
			testCases = []expectedNetPolValues{
				{0, 0, netPolPromVals{0, 1, 0, 1}},
			}
			checkNetPolTestResult("TestCountsDelNetPol", f, testCases)
			require.Equal(t, 0, metrics.GetCidrNetPols())
			require.Equal(t, 0, metrics.GetNamedPortNetPols())
		})
	}
}

func TestCountsUpdateNetPol(t *testing.T) {
	tests := []struct {
		name                  string
		netPolSpec            *networkingv1.NetworkPolicySpec
		updatedNetPolSpec     *networkingv1.NetworkPolicySpec
		cidrCount             int
		namedPortCount        int
		updatedCidrCount      int
		updatedNamedPortCount int
	}{
		{
			name: "cidr-to-no-cidr",
			netPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						From: []networkingv1.NetworkPolicyPeer{
							{
								IPBlock: &networkingv1.IPBlock{
									CIDR: "0.0.0.0/0",
								},
							},
						},
					},
				},
			},
			updatedNetPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						From: []networkingv1.NetworkPolicyPeer{
							{
								PodSelector: &metav1.LabelSelector{
									MatchLabels: map[string]string{"app": "test"},
								},
							},
						},
					},
				},
			},
			cidrCount:        1,
			updatedCidrCount: 0,
		},
		{
			name: "no-cidr-to-cidr",
			netPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						From: []networkingv1.NetworkPolicyPeer{
							{
								PodSelector: &metav1.LabelSelector{
									MatchLabels: map[string]string{"app": "test"},
								},
							},
						},
					},
				},
			},
			updatedNetPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						From: []networkingv1.NetworkPolicyPeer{
							{
								IPBlock: &networkingv1.IPBlock{
									CIDR: "0.0.0.0/0",
								},
							},
						},
					},
				},
			},
			cidrCount:        0,
			updatedCidrCount: 1,
		},
		{
			name: "cidr-to-cidr",
			netPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						From: []networkingv1.NetworkPolicyPeer{
							{
								IPBlock: &networkingv1.IPBlock{
									CIDR: "0.0.0.0/0",
								},
							},
						},
					},
				},
			},
			updatedNetPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						From: []networkingv1.NetworkPolicyPeer{
							{
								IPBlock: &networkingv1.IPBlock{
									CIDR: "1.0.0.0/32",
								},
							},
						},
					},
				},
			},
			cidrCount:        1,
			updatedCidrCount: 1,
		},
		{
			name: "namedPort-to-no-namedPort",
			netPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						Ports: []networkingv1.NetworkPolicyPort{
							{
								Port: &intstr.IntOrString{StrVal: "abc"},
							},
						},
					},
				},
			},
			updatedNetPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						Ports: []networkingv1.NetworkPolicyPort{
							{
								Port: &intstr.IntOrString{IntVal: 8000},
							},
						},
					},
				},
			},
			namedPortCount:        1,
			updatedNamedPortCount: 0,
		},
		{
			name: "no-namedPort-to-namedPort",
			netPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						Ports: []networkingv1.NetworkPolicyPort{
							{
								Port: &intstr.IntOrString{IntVal: 8000},
							},
						},
					},
				},
			},
			updatedNetPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						Ports: []networkingv1.NetworkPolicyPort{
							{
								Port: &intstr.IntOrString{StrVal: "abc"},
							},
						},
					},
				},
			},
			namedPortCount:        0,
			updatedNamedPortCount: 1,
		},
		{
			name: "namedPort-to-namedPort",
			netPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						Ports: []networkingv1.NetworkPolicyPort{
							{
								Port: &intstr.IntOrString{StrVal: "abc"},
							},
						},
					},
				},
			},
			updatedNetPolSpec: &networkingv1.NetworkPolicySpec{
				PolicyTypes: []networkingv1.PolicyType{
					networkingv1.PolicyTypeIngress,
				},
				Ingress: []networkingv1.NetworkPolicyIngressRule{
					{
						Ports: []networkingv1.NetworkPolicyPort{
							{
								Port: &intstr.IntOrString{StrVal: "xyz"},
							},
						},
					},
				},
			},
			namedPortCount:        1,
			updatedNamedPortCount: 1,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			f := newNetPolFixture(t)
			netPolObj := createNetPol()
			netPolObj.Spec = *tt.netPolSpec
			f.netPolLister = append(f.netPolLister, netPolObj)
			f.kubeobjects = append(f.kubeobjects, netPolObj)
			stopCh := make(chan struct{})
			defer close(stopCh)
			ctrl := gomock.NewController(t)
			defer ctrl.Finish()

			dp := dpmocks.NewMockGenericDataplane(ctrl)
			f.newNetPolController(stopCh, dp, false)

			dp.EXPECT().UpdatePolicy(gomock.Any()).Times(2)

			addNetPol(f, netPolObj)
			testCases := []expectedNetPolValues{
				{1, 0, netPolPromVals{1, 1, 0, 0}},
			}
			checkNetPolTestResult("TestCountsAddNetPol", f, testCases)
			require.Equal(t, tt.cidrCount, metrics.GetCidrNetPols())
			require.Equal(t, tt.namedPortCount, metrics.GetNamedPortNetPols())

			newNetPolObj := createNetPol()
			newNetPolObj.Spec = *tt.updatedNetPolSpec
			newRV, _ := strconv.Atoi(netPolObj.ResourceVersion)
			newNetPolObj.ResourceVersion = fmt.Sprintf("%d", newRV+1)
			updateNetPol(t, f, netPolObj, newNetPolObj)
			testCases = []expectedNetPolValues{
				{1, 0, netPolPromVals{1, 1, 1, 0}},
			}
			checkNetPolTestResult("TestCountsUpdateNetPol", f, testCases)
			require.Equal(t, tt.updatedCidrCount, metrics.GetCidrNetPols())
			require.Equal(t, tt.updatedNamedPortCount, metrics.GetNamedPortNetPols())
		})
	}
}
