// Copyright (C) 2026 32bitmicro LLC
// SPDX-License-Identifier: AGPL-3.0-or-later

import cpu;
import gpio;
import uart;
import stdio;
import mcp;

namespace {

mmcu::mcp::tool_result write_gpio_tool(
    const mmcu::mcp::json_document& document,
    const mmcu::mcp::json_value& arguments
)
{
    const auto* pin_value = document.member(arguments, "pin");
    const auto* output_value = document.member(arguments, "value");

    if (pin_value == nullptr || output_value == nullptr) {
        return mmcu::mcp::tool_text_result("missing pin or value", true);
    }
    if (pin_value->type != mmcu::mcp::json_type::number || output_value->type != mmcu::mcp::json_type::number) {
        return mmcu::mcp::tool_text_result("pin and value must be numbers", true);
    }

    const auto pin = static_cast<unsigned>(pin_value->number);
    const auto high = output_value->number != 0;

    mmcu::gpio::gpio0.configure(pin, mmcu::gpio::direction::output);
    if (high) {
        mmcu::gpio::gpio0.set(pin);
    } else {
        mmcu::gpio::gpio0.clear(pin);
    }

    return mmcu::mcp::tool_text_result("GPIO write complete");
}

}

int main() asm("main");

int main()
{
    mmcu::stdio::initialize();
    static_cast<void>(mmcu::cpu::core);
    static_cast<void>(mmcu::gpio::gpio0);
    static_cast<void>(mmcu::uart::uart0);

    mmcu::uart::uart0.configure({
        .baud_rate = 115200,
        .data_bits = 8,
        .parity_mode = mmcu::uart::parity::none,
        .stop = mmcu::uart::stop_bits::one,
        .flow = mmcu::uart::flow_control::none,
    });

    mmcu::mcp::server server;
    server.register_tool(
        "write_gpio",
        write_gpio_tool,
        "Configure a GPIO pin as output and write a digital value.",
        "{\"type\":\"object\",\"properties\":{\"pin\":{\"type\":\"integer\"},\"value\":{\"type\":\"integer\"}},\"required\":[\"pin\",\"value\"]}"
    );
    server.run();

    for (;;) {
        mmcu::cpu::core.wait_for_event();
    }
}
