// Local compatibility for the pinned Qwen3.5 loader only.
// conversion/base.py pads three MRoPE dimensions to four; conversion/qwen.py
// writes [11, 11, 10, 0] for Qwen3.5. Keep the original GGUF bytes untouched.
#pragma once
#include <array>
#include <cstdint>
#include <stdexcept>
#include <vector>

inline std::array<int32_t, 4> archi_qwen35_mrope_sections(const std::vector<int32_t> & input) {
    if (input.size() == 4) {
        return {input[0], input[1], input[2], input[3]};
    }
    // Restrict the compatibility exception to the observed Qwen3.5 layout.
    if (input == std::vector<int32_t>{11, 11, 10}) {
        return {11, 11, 10, 0};
    }
    throw std::runtime_error("Unsupported Qwen3.5 MRoPE sections; expected four entries or [11,11,10]");
}
