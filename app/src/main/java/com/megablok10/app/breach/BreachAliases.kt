package com.megablok10.app.breach

/*
 * Чистая логика взлома живёт в общем модуле правил (:rules, пакет com.megablok10.rules) — её же вызывает Мост «Сети».
 * Здесь псевдонимы, чтобы код приложения не менял импорты (как у Tier и DaemonEffect — те лежат рядом, в своих файлах). Функции (generateGrid,
 * resolveDaemons, nextLinkDimension, candidatesFor) под псевдоним не подпадают — вызывающие импортируют их из :rules.
 */
typealias Daemon = com.megablok10.rules.Daemon
typealias LinkDimension = com.megablok10.rules.LinkDimension
typealias BreachGrid = com.megablok10.rules.BreachGrid
typealias BreachSymbols = com.megablok10.rules.BreachSymbols
typealias BreachParams = com.megablok10.rules.BreachParams
typealias BreachTierParams = com.megablok10.rules.BreachTierParams
typealias BreachAttemptState = com.megablok10.rules.BreachAttemptState
typealias BreachResult = com.megablok10.rules.BreachResult
typealias BreachOutcome = com.megablok10.rules.BreachOutcome
typealias BreachTap = com.megablok10.rules.BreachTap
typealias BreachRun = com.megablok10.rules.BreachRun
typealias BreachAutoSolver = com.megablok10.rules.BreachAutoSolver
typealias ContainerEddies = com.megablok10.rules.ContainerEddies
typealias DecryptRules = com.megablok10.rules.DecryptRules
typealias IceEvent = com.megablok10.rules.IceEvent
typealias IceLines = com.megablok10.rules.IceLines
typealias LootType = com.megablok10.rules.LootType
typealias LootSlot = com.megablok10.rules.LootSlot
typealias Container = com.megablok10.rules.Container
