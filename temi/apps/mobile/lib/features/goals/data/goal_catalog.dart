/// Goals reuse the category catalog for their visual identity — same icon
/// set, same 10-color swatch — so user-created goals feel native alongside
/// categories without introducing yet another palette to maintain.
///
/// Keep this file as a pure re-export; if goal-only icons/colors ever
/// emerge they can be added on top, but the base sets stay shared.
library;

export '../../categories/data/category_catalog.dart'
    show kCategoryIconCatalog, kCategoryColorCatalog, iconForCategory;
