# TreeverseAlgorithm

[![Build Status](https://github.com/GiggleLiu/TreeverseAlgorithm.jl/workflows/CI/badge.svg)](https://github.com/GiggleLiu/TreeverseAlgorithm.jl/actions)


Treeverse algorithm described in

[Achieving logarithmic growth of temporal and spatial complexity in reverse automatic differentiation](https://www.tandfonline.com/doi/abs/10.1080/10556789208805505), 1992, By Andreas Griewank

Treeverse alorithm is one of the corner stones in automatic differentiation towards solving the memory wall issue, and this package aims to solve the memory wall issue in differentiating physics simulation. But, it has not been optimized for solving small scale problems or differentiating a general program.

```julia
julia> using TreeverseAlgorithm

julia> using Viznet
┌ Info: TreeverseAlgorithm: You just imported `Viznet`, you can use
└     * (image, nstep) = treeverse_pebblegame(N, δ)

julia> treeverse_pebblegame(30, 5)[1]
Treeverse peak memory = 6
```
<img src="assets/treeverse-pebble-30-5.svg" width=300/>

In this diagram, there are 31 columns representing state 0-30.
Each row represents a single step forward computing.
In each row, there is one black dot representing the state computed in current step,
several empty dots representing states deallocated in currect step,
and some gray dots representing checkpoints stored in the global memory.
Grids with red color means gradient has been computed.

There is a theoretical model to understand what treeverse is doing here - the **checkpointing version pebble game**.
Pebble game is a board game defined on a 1D grid that originally used to represent the time-space tradeoff in reversible programming. The checkpointing version is: you have `S` pebbles and one red pen. At the beginning of the game, the first grid has a pebble and the last grid is doodled with red. In each step, you need to follow the following rules

* put rule: Only if there exists a pebble in grid `i`, you can move a pebble from your own pool to the grid `i+1`,
* take rule: you can take a pebble from the board any time,
* doodle rule: you can doodle grid `i` only it when this grid has a pebble in it and grid `i+1` is red,
* end rule: doodle all grids.

The goal is to trigger game ending with the least number of steps (put rule), and the (approximately) optimal solution is the treeverse algorithm.

## Example
For an example of using Treeverse in revese mode autodiff, please check the [test file](test/treeverse.jl).
