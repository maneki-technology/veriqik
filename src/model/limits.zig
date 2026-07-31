/// Collection items are parsed before count limits are enforced so syntax errors take precedence.
pub const Limits = struct {
    source_bytes_max: u32 = 1 * 1024 * 1024,
    identifier_bytes_max: u8 = 255,

    types_max: u16 = 1_024,
    conditions_max: u16 = 1_024,
    relations_per_type_max: u16 = 1_024,
    parameters_per_condition_max: u8 = 64,

    symbol_count_max: u32 = 1 << 16,
};
