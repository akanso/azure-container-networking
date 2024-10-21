package restserver

import (
	"context"
	"net/netip"

	"github.com/Azure/azure-container-networking/cns"
	"github.com/Azure/azure-container-networking/cns/common"
	"github.com/Azure/azure-container-networking/cns/fakes"
	"github.com/Azure/azure-container-networking/cns/nodesubnet"
	acn "github.com/Azure/azure-container-networking/common"
	"github.com/Azure/azure-container-networking/nmagent"
	"github.com/Azure/azure-container-networking/store"
)

func GetRestServiceObjectForNodeSubnetTest(generator CNIConflistGenerator) *HTTPRestService {
	config := &common.ServiceConfig{
		Name:        "test",
		Version:     "1.0",
		ChannelMode: "AzureHost",
		Store:       store.NewMockStore("test"),
	}
	interfaces := nmagent.Interfaces{
		Entries: []nmagent.Interface{
			{
				MacAddress: nmagent.MACAddress{0x00, 0x0D, 0x3A, 0xF9, 0xDC, 0xA6},
				IsPrimary:  true,
				InterfaceSubnets: []nmagent.InterfaceSubnet{
					{
						Prefix: "10.240.0.0/16",
						IPAddress: []nmagent.NodeIP{
							{
								Address:   nmagent.IPAddress(netip.AddrFrom4([4]byte{10, 240, 0, 5})),
								IsPrimary: true,
							},
							{
								Address:   nmagent.IPAddress(netip.AddrFrom4([4]byte{10, 240, 0, 6})),
								IsPrimary: false,
							},
						},
					},
				},
			},
		},
	}

	svc, err := cns.NewService(config.Name, config.Version, config.ChannelMode, config.Store)
	if err != nil {
		return nil
	}

	svc.SetOption(acn.OptCnsURL, "")
	svc.SetOption(acn.OptCnsPort, "")
	err = svc.Initialize(config)
	if err != nil {
		return nil
	}

	return &HTTPRestService{
		Service:              svc,
		cniConflistGenerator: generator,
		state:                &httpRestServiceState{},
		PodIPConfigState:     make(map[string]cns.IPConfigurationStatus),
		nma: &fakes.NMAgentClientFake{
			GetInterfaceIPInfoF: func(_ context.Context) (nmagent.Interfaces, error) {
				return interfaces, nil
			},
		},
	}
}

// SetCNIConflistGenerator sets the CNIConflistGenerator for the HTTPRestService.
func (service *HTTPRestService) SetCNIConflistGenerator(generator CNIConflistGenerator) {
	service.cniConflistGenerator = generator
}

// GetNodesubnetIPFetcher gets the nodesubnet.IPFetcher from the HTTPRestService.
func (service *HTTPRestService) GetNodesubnetIPFetcher() *nodesubnet.IPFetcher {
	return service.nodesubnetIPFetcher
}
