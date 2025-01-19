---
layout: post
title: Building RDB from scratch - 01. B+ Tree
description: Exploring the importance of B+ trees in building a tiny relational database (RDB) and reflecting on the implementation insights gained from examining an open-source B+ tree library.
summary: This post delves into why B+ trees are essential for a tiny relational database and discusses key learnings from reviewing the collinglass/bptree implementation.
tags: [css]
---

### 1. Why B+ tree?
When starting the construction of a lightweight relational database, the B+ tree emerges as a fundamental data structure. Its inherent ability to efficiently index and retrieve data renders it indispensable for managing structured information. Unlike traditional binary search trees, the B+ tree is specifically optimized for disk-based storage, minimizing the number of I/O operations required to access data—a crucial consideration for any relational database where data typically resides on disk, not solely in memory. Thus, the B+ tree is not merely a beneficial option, but rather a cornerstone for any viable small-scale RDB.  
Furthermore, examining the implementation details of a B+ tree, such as those found in the open-source `collinglass/bptree` library, offers valuable insights into practical database design and implementation, which I will explore in this post.

### 2. Implementations

#### 1) Core Data Structures
```gotemplate
type Tree struct {
	Root *Node
}

type Record struct {
	Value []byte
}

type Node struct {
	Pointers []interface{}
	Keys     []int
	Parent   *Node
	IsLeaf   bool
	NumKeys  int
	Next     *Node
}
```
Tree represents the entire B+ tree structure, with the Root field serving as the entry point to the tree. It is a basic and clear way to represent the whole B+ tree structure.  
Record struct separates keys from their byte array values ([]byte), allowing the library to handle diverse data types as long as they can be serialized.  
Node represents a single B+ tree node, which holds Pointers (to child nodes or record values), Keys, a Parent pointer, a flag for IsLeaf, NumKeys tracking the number of valid keys, and a Next pointer for linked list of leaf nodes. The interface{} type for Pointers enables handling both nodes and records, and NumKeys ensures performance optimization to determine the number of valid keys.  

#### 2) Insertion

```gotemplate
func (t *Tree) Insert(key int, value []byte) error {
	// ...
	if t.Root == nil {
		return t.startNewTree(key, pointer)
	}
	// ...
    leaf = t.findLeaf(key, false)
    
	if leaf.NumKeys < order-1 {
		insertIntoLeaf(leaf, key, pointer)
		return nil
	}

	return t.insertIntoLeafAfterSplitting(leaf, key, pointer)
}
```
The insertion process first checks for a root node, creating a new tree if necessary. It locates the correct leaf node via t.findLeaf and then inserts the key if there's capacity, using insertIntoLeaf as a helper method. When the leaf is full, t.insertIntoLeafAfterSplitting handles the node split, utilizing temporary arrays and demonstrating a "copy-on-write" approach where a new node is created during splits to keep the B+ tree balanced.

#### 3) Searching
```gotemplate
func (t *Tree) Find(key int, verbose bool) (*Record, error) {
	i := 0
	c := t.findLeaf(key, verbose)
	if c == nil {
		return nil, errors.New("key not found")
	}
	for i = 0; i < c.NumKeys; i++ {
		if c.Keys[i] == key {
			break
		}
	}
	if i == c.NumKeys {
		return nil, errors.New("key not found")
	}

	r, _ := c.Pointers[i].(*Record)

	return r, nil
}
```
The search starts with the private findLeaf function, which recursively navigates the tree to locate the appropriate leaf node. Within the leaf node, a loop iterates through the keys to find a match. Upon finding a matching key, the associated value is returned after a type assertion to the Record type. This search logic demonstrates how each node acts as a decision point, guiding the traversal along the correct search path to find the target key.


#### 4) Deletion
```gotemplate
func (t *Tree) Delete(key int) error {
	key_record, err := t.Find(key, false)
	if err != nil {
		return err
	}
	key_leaf := t.findLeaf(key, false)
	if key_record != nil && key_leaf != nil {
		t.deleteEntry(key_leaf, key, key_record)
	}
	return nil
}
```
The deletion process begins by using t.Find and t.findLeaf to locate the target node and key. Once found, the t.deleteEntry method is invoked, which orchestrates a complex deletion procedure. This involves removeEntryFromNode to remove the key from the node, and then a series of other operations: adjustRoot to handle root node modifications, and either coalesceNodes or redistributeNodes to maintain the B+ tree's balance through merging or redistributing nodes, respectively.


