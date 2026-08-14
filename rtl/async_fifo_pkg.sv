package async_fifo_pkg;
    function automatic logic is_power_of_two(input integer value);
        return (value >= 2) && ((value & (value - 1)) == 0);
    endfunction
endpackage