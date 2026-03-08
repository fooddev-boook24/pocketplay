# PocketPlay AI Development Rules

This repository implements the PocketPlay board game discovery app.

The core feature is a **realistic board game store shelf UI** inspired by Jelly Jelly Store.

This project must NOT produce a generic shopping grid UI.

## Core Visual Goal

The user must feel like they are browsing a real store shelf.

The shelf must contain:

- spine boxes
- face boxes
- stack boxes
- dense arrangement
- warm store lighting
- thin wooden shelf boards

## Important Design Rules

Shelf board thickness must be approximately **18–22px**.

Box spacing should be **2–6px**.

The shelf must look dense.

Avoid large empty areas.

Small colorful spine boxes are important.

Reference images inside `sample_assets/` must guide the layout.

## Forbidden Implementations

Do NOT:

- use GridView as the main layout
- render product cards
- create ecommerce-style UI
- render reference photos as shelf content
- produce placeholder colored boxes
- space boxes widely

## Rendering Approach

Preferred Flutter widgets:

Stack  
Positioned  
Transform  
CustomScrollView  
SliverList  
RepaintBoundary

## Architecture

Core components:

ShelfPlacementEngine  
ShelfPlacement  
ShelfRow  
GameBox

GameBox must support three poses:

spine  
face  
stack

The ShelfPlacementEngine must generate realistic dense shelf layouts.

## Implementation Order

1 Read specification file  
2 Inspect reference assets  
3 Implement ShelfPlacementEngine  
4 Implement ShelfRow  
5 Implement GameBox  
6 Build HomeScreen  
7 Add performance optimizations

UI must only be implemented after placement logic exists.