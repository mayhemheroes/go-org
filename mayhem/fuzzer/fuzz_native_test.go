//go:build ignore
// Preserved from the pre-port fork (archive/original-master org/fuzz_native_test.go)
// for harness parity. The active harness is upstream org/fuzz.go (built by mayhem/build.sh);
// this native wrapper is kept for reference only and is not compiled.

package org

import (
	"bytes"
	"strings"
	"testing"
)

// FuzzParser is a native Go fuzzing wrapper around the legacy go-fuzz Fuzz function.
func FuzzParser(f *testing.F) {
	f.Add([]byte("* Hello\nsome paragraph\n"))
	f.Fuzz(func(t *testing.T, input []byte) {
		conf := New().Silent()
		d := conf.Parse(bytes.NewReader(input), "")
		orgOutput, err := d.Write(NewOrgWriter())
		if err != nil {
			return
		}
		htmlOutputA, err := d.Write(NewHTMLWriter())
		if err != nil {
			return
		}
		htmlOutputB, _ := conf.Parse(strings.NewReader(orgOutput), "").Write(NewHTMLWriter())
		_ = htmlOutputA
		_ = htmlOutputB
	})
}
