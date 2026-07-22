/// Collection items are parsed before count limits are enforced so syntax errors take precedence.
pub const Limits = struct {
    source_bytes_max: usize = 1 * 1024 * 1024,
    identifier_bytes_max: usize = 255,

    types_max: usize = 1_024,
    conditions_max: usize = 1_024,
    relations_per_type_max: usize = 1_024,
    parameters_per_condition_max: usize = 64,

    symbol_count_max: usize = 1 << 16,
};
