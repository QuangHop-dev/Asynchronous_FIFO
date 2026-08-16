# Asynchronous FIFO

A parameterized asynchronous FIFO for reliable data transfer between independent clock domains.

## Project Status

Work in progress.

This repository is being developed incrementally from the specification through RTL design and verification.

## Planned Features

- Independent write and read clock domains
- Parameterized data width and FIFO depth
- Binary and Gray-coded pointers
- CDC-safe pointer synchronization
- Full and empty detection
- Standard and First-Word Fall-Through read modes
- Almost-full and almost-empty indicators
- Overflow and underflow detection
- Optional coordinated reset handling

## Project Structure

```text
async-fifo/
├── docs/
│   └── specification.md
├── README.md
└── .gitignore