module main

import os

pub struct FileTreeEntry {
pub:
	name      string
	typ       string // 'file' or 'folder'
	padding   int
	full_path string
	is_open   bool
}

struct FileTreeItem {
	name      string
	full_path string
	is_dir    bool
mut:
	is_open  bool
	children []string
}

pub struct FileTree {
	root string
mut:
	nodes map[string]&FileTreeItem
}

pub fn new_file_tree(root string) &FileTree {
	absolute := os.real_path(root)
	mut tree := &FileTree{
		root:  absolute
		nodes: map[string]&FileTreeItem{}
	}
	tree.nodes[absolute] = &FileTreeItem{
		name:      os.file_name(absolute)
		full_path: absolute
		is_dir:    true
		is_open:   true
	}
	tree.ensure_children(absolute)
	return tree
}

pub fn (mut t FileTree) toggle(path string) {
	mut item := t.nodes[path] or { return }
	if !item.is_dir {
		return
	}
	item.is_open = !item.is_open
	if item.is_open {
		t.ensure_children(path)
	}
}

pub fn (mut t FileTree) flattened() []FileTreeEntry {
	mut entries := []FileTreeEntry{}
	t.ensure_children(t.root)
	mut root := t.nodes[t.root] or { return entries }
	for child_path in root.children {
		t.collect(child_path, 0, mut entries)
	}
	return entries
}

pub fn (mut t FileTree) refresh_open_nodes() {
	t.refresh_recursive(t.root)
}

fn (mut t FileTree) refresh_recursive(path string) {
	t.ensure_children(path)
	mut item := t.nodes[path] or { return }
	for child in item.children {
		if child_item := t.nodes[child] {
			if child_item.is_dir && child_item.is_open {
				t.refresh_recursive(child)
			}
		}
	}
}

fn (mut t FileTree) collect(path string, depth int, mut entries []FileTreeEntry) {
	mut item := t.nodes[path] or { return }
	entry_type := if item.is_dir { 'folder' } else { 'file' }
	entries << FileTreeEntry{
		name:      item.name
		typ:       entry_type
		padding:   depth
		full_path: item.full_path
		is_open:   item.is_open
	}
	if !item.is_dir || !item.is_open {
		return
	}
	t.ensure_children(path)
	for child in item.children {
		t.collect(child, depth + 1, mut entries)
	}
}

fn (mut t FileTree) ensure_children(path string) {
	mut item := t.nodes[path] or { return }
	if !item.is_dir {
		return
	}
	entries := os.ls(path) or {
		item.children = []string{}
		return
	}
	mut directories := []string{}
	mut files := []string{}
	for name in entries {
		full := os.join_path(path, name)
		if os.is_dir(full) {
			directories << full
		} else {
			files << full
		}
	}
	directories.sort()
	files.sort()
	mut children := []string{}
	for full in directories {
		_ = t.nodes[full] or {
			mut created := &FileTreeItem{
				name:      os.file_name(full)
				full_path: full
				is_dir:    true
			}
			t.nodes[full] = created
			created
		}
		children << full
	}
	for full in files {
		_ = t.nodes[full] or {
			mut created := &FileTreeItem{
				name:      os.file_name(full)
				full_path: full
				is_dir:    false
			}
			t.nodes[full] = created
			created
		}
		children << full
	}
	item.children = children
}
