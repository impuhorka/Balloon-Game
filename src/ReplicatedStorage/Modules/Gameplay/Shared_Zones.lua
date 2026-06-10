local Zones = {}

Zones.List = {
    [1] = {
        DisplayName = "Zone 1",

        LuckyBlockChances = {
            CommonLuckyBlock = 70,
            RareLuckyBlock = 30,
        },

        LuckyBlocks_PerSpawner = 1, -- max on each SpawnArea part OR each SpawnAreas model (not shared across whole zone)
    },
    [2] = {
        DisplayName = "Zone 2",

        LuckyBlockChances = {
            RareLuckyBlock = 30,
            EpicLuckyBlock = 70,
        },

        LuckyBlocks_PerSpawner = 1, -- max on each SpawnArea part OR each SpawnAreas model (not shared across whole zone)
    },
    [3] = {
        DisplayName = "Zone 3",

        LuckyBlockChances = {
            EpicLuckyBlock = 30,
            LegendaryLuckyBlock = 70,
        },

        LuckyBlocks_PerSpawner = 1, -- max on each SpawnArea part OR each SpawnAreas model (not shared across whole zone)
    },
    [4] = {
        DisplayName = "Zone 4",

        LuckyBlockChances = {
            LegendaryLuckyBlock = 30,
            MythicalLuckyBlock = 70,
        },

        LuckyBlocks_PerSpawner = 1, -- max on each SpawnArea part OR each SpawnAreas model (not shared across whole zone)
    },
}

return Zones