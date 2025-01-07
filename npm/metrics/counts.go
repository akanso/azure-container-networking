package metrics

import "sync"

var nonPrometheusCounts *counts

// counts is a struct holding non-Prometheus counts.
type counts struct {
	sync.Mutex
	cidrNetPols      int
	namedPortNetPols int
}

func IncCidrNetPols() {
	if nonPrometheusCounts == nil {
		return
	}
	nonPrometheusCounts.Lock()
	defer nonPrometheusCounts.Unlock()
	nonPrometheusCounts.cidrNetPols++
}

func DecCidrNetPols() {
	if nonPrometheusCounts == nil {
		return
	}
	nonPrometheusCounts.Lock()
	defer nonPrometheusCounts.Unlock()
	nonPrometheusCounts.cidrNetPols--
}

func GetCidrNetPols() int {
	if nonPrometheusCounts == nil {
		return 0
	}
	nonPrometheusCounts.Lock()
	defer nonPrometheusCounts.Unlock()
	return nonPrometheusCounts.cidrNetPols
}

func IncNamedPortNetPols() {
	if nonPrometheusCounts == nil {
		return
	}
	nonPrometheusCounts.Lock()
	defer nonPrometheusCounts.Unlock()
	nonPrometheusCounts.namedPortNetPols++
}

func DecNamedPortNetPols() {
	if nonPrometheusCounts == nil {
		return
	}
	nonPrometheusCounts.Lock()
	defer nonPrometheusCounts.Unlock()
	nonPrometheusCounts.namedPortNetPols--
}

func GetNamedPortNetPols() int {
	if nonPrometheusCounts == nil {
		return 0
	}
	nonPrometheusCounts.Lock()
	defer nonPrometheusCounts.Unlock()
	return nonPrometheusCounts.namedPortNetPols
}
