# Specification

## Scope

The `async_fifo` transfers data in the correct order from the `wr_clk` domain to the `rd_clk` domain. The two clocks do not require any specific frequency or phase relationship.

## Interface

| Port | Domain | Direction | Meaning |
|---|---|---|---|
| `wr_clk`, `wr_rst_n` | write | input | Clock and external active-low reset |
| `wr_en`, `wr_data` | write | input | Write request và payload |
| `wr_full` | write | output | Block write, including safe-reset rendezvous |
| `wr_almost_full` | write | output | `wr_level >= ALMOST_FULL_THRESHOLD` |
| `wr_level` | write | output | `wr_bin - synchronized(rd_bin)` |
| `wr_overflow` | write | output | Pulse following request while in full state |
| `rd_clk`, `rd_rst_n` | read | input | Clock and external active-low reset |
| `rd_en` | read | input | Read/consume request |
| `rd_data`, `rd_valid` | read | output | Read payload and valid indication |
| `rd_empty` | read | output | Block read, including safe-reset rendezvous |
| `rd_almost_empty` | read | output | `rd_level <= ALMOST_EMPTY_THRESHOLD` |
| `rd_level` | read | output | `synchronized(wr_bin) - rd_bin` |
| `rd_underflow` | read | output | Pulse following request while in empty status |

## Transaction Contract

```text
wr_accept = wr_en && !wr_full
rd_accept = rd_en && !rd_empty
```

When write operation is blocked, write pointer and memory remain unchanged. When read operation is blocked, read pointer remain unchanged and no item is consumed. No transactions are accepted during safe-reset rendezvous due to `wr_full = 1` and `rd_empty = 1`.

`wr_overflow` and `rd_underflow` are registed, single-cycle pulses reflecting rejected request from previous cycle.

## Read mode

In Standard mode (`FWWFT_ENABLE=0`), RAM is read on accepted read edge. `rd_data` and `rd_valid` reflect the item consummed after that edge.

In FWFT mode (`FWFT_ENABLE=1`), the head item is presented when FIFO is non-empty. In the operation state, `rd_valid == !rd_empty`; rd_en consumes current head item.

## Level and threshold

`wr_level` and `rd_level` are modulo pointer differences with a width of `$clog2(DEPTH+1)`. Because the remote pointers pass through a synchronizer, they do not represent a global instantaneous count. Each level is stable relative to the local clock and is conservative: the write side may not yet see a new read, and the read side may not yet see a new write. During an inactive or reset rendezvous, both levels return 0, and the "almost-full" and "almost-empty" signals are both asserted to indicate a blocked state.

## Reset contract

- Assertion is asynchronous.
- Deassertion local is synchronous after `SYNC_STAGES` clock edges.
- Safe mode: any external reset requires a global flush; the entire domain is blocked until the ready signal is bi-directionally synchronized.
- Basic mode: the integration must assert both `wr_rst_n` and `rd_rst_n`; independent resets are not a part of the contract.
- Memory bit are not reset. Resetting pointer to 0 rendets all pre-reset entries invalid.

## Parameter checking

RTL issues a `$fatal` error at elaboration/time zero if `DATA_WIDTH==0`, `DEPTH<2`,
`DEPTH` is not a power of two, `SYNC_STAGES<2`, or threshold exceeds `DEPTH`.
These checks are wrapperd in `ifndef SYNTHESIS`.