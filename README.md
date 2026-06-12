# Veriqik

A purpose-built database concept for fine-grained authorization.

This repository is currently documentation-first. The Zig implementation under [prototype](prototype) is an exploratory prototype used to learn about Veriqik's domain model, DSL, indexing shape, load testing, and benchmark requirements. It is not intended to become production code.

Start with [docs/README.md](docs/README.md) for product, domain, architecture, roadmap, and MVP documentation.

To run the prototype:

```sh
cd prototype
zig build test
zig build run -- demo
zig build run -- load-plan
```
