package restserver_test

import (
	"context"
	"testing"

	"github.com/Azure/azure-container-networking/cns"
	"github.com/Azure/azure-container-networking/cns/logger"
	"github.com/Azure/azure-container-networking/cns/restserver"
)

// Mock implementation of PodInfoByIPProvider
type MockPodInfoByIPProvider struct{}

func (m *MockPodInfoByIPProvider) PodInfoByIP() (res map[string]cns.PodInfo, err error) {
	return res, nil
}

// Mock implementation of CNIConflistGenerator
type MockCNIConflistGenerator struct {
	GenerateCalled chan struct{}
}

func (m *MockCNIConflistGenerator) Generate() error {
	close(m.GenerateCalled)
	return nil
}

func (m *MockCNIConflistGenerator) Close() error {
	// Implement the Close method logic here if needed
	return nil
}

func TestNodeSubnet(t *testing.T) {
	mockPodInfoProvider := &MockPodInfoByIPProvider{}

	// Create a real HTTPRestService object
	mockCNIConflistGenerator := &MockCNIConflistGenerator{
		GenerateCalled: make(chan struct{}),
	}
	service := restserver.GetRestServiceObjectForNodeSubnetTest(t, mockCNIConflistGenerator)
	ctx, cancel := testContext(t)
	defer cancel()

	err := service.InitializeNodeSubnet(ctx, mockPodInfoProvider)
	service.StartNodeSubnet(ctx)

	if service.GetNodesubnetIPFetcher() == nil {
		t.Error("NodeSubnetIPFetcher is not initialized")
	}

	if err != nil {
		t.Fatalf("InitializeNodeSubnet returned an error: %v", err)
	}

	select {
	case <-ctx.Done():
		t.Errorf("test context done - %s", ctx.Err())
		return
	case <-mockCNIConflistGenerator.GenerateCalled:
		break
	}
}

// testContext creates a context from the provided testing.T that will be
// canceled if the test suite is terminated.
func testContext(t *testing.T) (context.Context, context.CancelFunc) {
	if deadline, ok := t.Deadline(); ok {
		return context.WithDeadline(context.Background(), deadline)
	}
	return context.WithCancel(context.Background())
}

func init() {
	logger.InitLogger("testlogs", 0, 0, "./")
}
