package org

import (
	"fmt"
	"strings"
)

type stringBuilder = strings.Builder

type OrgWriter struct {
	TagsColumn int // see org-tags-column
	stringBuilder
	indent string
}

var emphasisOrgBorders = map[string][]string{
	"_":   []string{"_", "_"},
	"*":   []string{"*", "*"},
	"/":   []string{"/", "/"},
	"+":   []string{"+", "+"},
	"~":   []string{"~", "~"},
	"=":   []string{"=", "="},
	"_{}": []string{"_{", "}"},
	"^{}": []string{"^{", "}"},
}

func NewOrgWriter() *OrgWriter {
	return &OrgWriter{
		TagsColumn: 77,
	}
}

func (w *OrgWriter) before(d *Document) {}
func (w *OrgWriter) after(d *Document) {
	w.writeFootnotes(d)
}

func (w *OrgWriter) emptyClone() *OrgWriter {
	wcopy := *w
	wcopy.stringBuilder = strings.Builder{}
	return &wcopy
}

func (w *OrgWriter) writeNodes(ns ...Node) {
	for _, n := range ns {
		switch n := n.(type) {
		case Comment:
			w.writeComment(n)
		case Keyword:
			w.writeKeyword(n)
		case NodeWithMeta:
			w.writeNodeWithMeta(n)
		case Headline:
			w.writeHeadline(n)
		case Block:
			w.writeBlock(n)

		case FootnoteDefinition:
			w.writeFootnoteDefinition(n)

		case List:
			w.writeList(n)
		case ListItem:
			w.writeListItem(n)

		case Table:
			w.writeTable(n)
		case TableHeader:
			w.writeTableHeader(n)
		case TableRow:
			w.writeTableRow(n)
		case TableSeparator:
			w.writeTableSeparator(n)

		case Paragraph:
			w.writeParagraph(n)
		case HorizontalRule:
			w.writeHorizontalRule(n)
		case Text:
			w.writeText(n)
		case Emphasis:
			w.writeEmphasis(n)
		case LineBreak:
			w.writeLineBreak(n)
		case ExplicitLineBreak:
			w.writeExplicitLineBreak(n)
		case RegularLink:
			w.writeRegularLink(n)
		case FootnoteLink:
			w.writeFootnoteLink(n)
		default:
			if n != nil {
				panic(fmt.Sprintf("bad node %#v", n))
			}
		}
	}
}

func (w *OrgWriter) writeHeadline(h Headline) {
	tmp := w.emptyClone()
	tmp.WriteString(strings.Repeat("*", h.Lvl))
	if h.Status != "" {
		tmp.WriteString(" " + h.Status)
	}
	if h.Priority != "" {
		tmp.WriteString(" [#" + h.Priority + "]")
	}
	tmp.WriteString(" ")
	tmp.writeNodes(h.Title...)
	hString := tmp.String()
	if len(h.Tags) != 0 {
		hString += " "
		tString := ":" + strings.Join(h.Tags, ":") + ":"
		if n := w.TagsColumn - len(tString) - len(hString); n > 0 {
			w.WriteString(hString + strings.Repeat(" ", n) + tString)
		} else {
			w.WriteString(hString + tString)
		}
	} else {
		w.WriteString(hString)
	}
	w.WriteString("\n")
	if len(h.Children) != 0 {
		w.WriteString(w.indent)
	}
	w.writeNodes(h.Children...)
}

func (w *OrgWriter) writeBlock(b Block) {
	w.WriteString(w.indent + "#+BEGIN_" + b.Name)
	if len(b.Parameters) != 0 {
		w.WriteString(" " + strings.Join(b.Parameters, " "))
	}
	w.WriteString("\n")

	if isRawTextBlock(b.Name) {
		for _, line := range strings.Split(b.Children[0].(Text).Content, "\n") {
			w.WriteString(w.indent + line + "\n")
		}
	} else {
		w.writeNodes(b.Children...)
	}
	w.WriteString(w.indent + "#+END_" + b.Name + "\n")
}

func (w *OrgWriter) writeFootnotes(d *Document) {
	fs := d.Footnotes
	if len(fs.Definitions) == 0 {
		return
	}
	w.WriteString("* " + fs.Title + "\n")
	for _, definition := range fs.Ordered() {
		if !definition.Inline {
			w.writeNodes(definition)
		}
	}
}

func (w *OrgWriter) writeFootnoteDefinition(f FootnoteDefinition) {
	w.WriteString(fmt.Sprintf("[fn:%s]", f.Name))
	if !(len(f.Children) >= 1 && isEmptyLineParagraph(f.Children[0])) {
		w.WriteString(" ")
	}
	w.writeNodes(f.Children...)
}

func (w *OrgWriter) writeParagraph(p Paragraph) {
	w.writeNodes(p.Children...)
	w.WriteString("\n")
}

func (w *OrgWriter) writeKeyword(k Keyword) {
	w.WriteString(w.indent + fmt.Sprintf("#+%s: %s\n", k.Key, k.Value))
}

func (w *OrgWriter) writeNodeWithMeta(n NodeWithMeta) {
	for _, ns := range n.Meta.Caption {
		w.WriteString("#+CAPTION: ")
		w.writeNodes(ns...)
		w.WriteString("\n")
	}
	for _, attributes := range n.Meta.HTMLAttributes {
		w.WriteString("#+ATTR_HTML: ")
		for i := 0; i < len(attributes)-1; i += 2 {
			w.WriteString(attributes[i] + " ")
			if strings.ContainsAny(attributes[i+1], "\t ") {
				w.WriteString(`"` + attributes[i+1] + `"`)
			} else {
				w.WriteString(attributes[i+1])
			}
		}
		w.WriteString("\n")
	}
	w.writeNodes(n.Node)
}

func (w *OrgWriter) writeComment(c Comment) {
	w.WriteString(w.indent + "#" + c.Content)
}

func (w *OrgWriter) writeList(l List) { w.writeNodes(l.Items...) }

func (w *OrgWriter) writeListItem(li ListItem) {
	w.WriteString(w.indent + li.Bullet + " ")
	liWriter := w.emptyClone()
	liWriter.indent = w.indent + strings.Repeat(" ", len(li.Bullet)+1)
	liWriter.writeNodes(li.Children...)
	w.WriteString(strings.TrimPrefix(liWriter.String(), liWriter.indent))
}

func (w *OrgWriter) writeTable(t Table) {
	w.writeNodes(t.Header)
	w.writeNodes(t.Rows...)
}

func (w *OrgWriter) writeTableHeader(th TableHeader) {
	w.writeTableColumns(th.Columns)
	w.writeNodes(th.Separator)
}

func (w *OrgWriter) writeTableRow(tr TableRow) {
	w.writeTableColumns(tr.Columns)
}

func (w *OrgWriter) writeTableSeparator(ts TableSeparator) {
	w.WriteString(w.indent + ts.Content + "\n")
}

func (w *OrgWriter) writeTableColumns(columns [][]Node) {
	w.WriteString(w.indent + "| ")
	for i, columnNodes := range columns {
		w.writeNodes(columnNodes...)
		w.WriteString(" |")
		if i < len(columns)-1 {
			w.WriteString(" ")
		}
	}
	w.WriteString("\n")
}

func (w *OrgWriter) writeHorizontalRule(hr HorizontalRule) {
	w.WriteString(w.indent + "-----\n")
}

func (w *OrgWriter) writeText(t Text) { w.WriteString(t.Content) }

func (w *OrgWriter) writeEmphasis(e Emphasis) {
	borders, ok := emphasisOrgBorders[e.Kind]
	if !ok {
		panic(fmt.Sprintf("bad emphasis %#v", e))
	}
	w.WriteString(borders[0])
	w.writeNodes(e.Content...)
	w.WriteString(borders[1])
}

func (w *OrgWriter) writeLineBreak(l LineBreak) {
	w.WriteString(strings.Repeat("\n"+w.indent, l.Count))
}

func (w *OrgWriter) writeExplicitLineBreak(l ExplicitLineBreak) {
	w.WriteString(`\\` + "\n" + w.indent)
}

func (w *OrgWriter) writeFootnoteLink(l FootnoteLink) {
	w.WriteString("[fn:" + l.Name)
	if l.Definition != nil {
		w.WriteString(":")
		w.writeNodes(l.Definition.Children[0].(Paragraph).Children...)
	}
	w.WriteString("]")
}

func (w *OrgWriter) writeRegularLink(l RegularLink) {
	if l.AutoLink {
		w.WriteString(l.URL)
	} else if l.Description == nil {
		w.WriteString(fmt.Sprintf("[[%s]]", l.URL))
	} else {
		descriptionWriter := w.emptyClone()
		descriptionWriter.writeNodes(l.Description...)
		description := descriptionWriter.String()
		w.WriteString(fmt.Sprintf("[[%s][%s]]", l.URL, description))
	}
}
