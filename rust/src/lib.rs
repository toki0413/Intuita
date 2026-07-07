mod conservation;
mod decidability;
mod morphism;
mod verification;

use godot::prelude::*;

struct IntuitaCore;

#[gdextension]
unsafe impl ExtensionLibrary for IntuitaCore {}
