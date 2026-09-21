//
//  CarCatalog.swift
//  fastAndCar
//
//  Static, bundled brand → common-models list for AddCarView's picker —
//  there's no live car-data API wired into the app, so this is a curated
//  (not exhaustive) offline set covering mainstream global + Turkey-common
//  nameplates. Never the only way in: both pickers also offer a manual
//  "kendi yaz" entry for anything missing here, since no static list can
//  cover every trim/generation/market variant.
//

import Foundation

enum CarCatalog {
    static let brands: [String] = models.keys.sorted()

    static func models(for brand: String) -> [String] {
        (models[brand] ?? []).sorted()
    }

    private static let models: [String: [String]] = [
        "Audi": ["A1", "A3", "A4", "A5", "A6", "A7", "A8", "Q2", "Q3", "Q4 e-tron", "Q5", "Q7", "Q8", "e-tron", "TT", "RS6", "S3", "S4"],
        "BMW": ["1 Series", "2 Series", "3 Series", "4 Series", "5 Series", "6 Series", "7 Series", "8 Series", "X1", "X2", "X3", "X4", "X5", "X6", "X7", "Z4", "i3", "i4", "iX"],
        "Mercedes-Benz": ["A-Class", "B-Class", "C-Class", "CLA", "CLS", "E-Class", "S-Class", "G-Class", "GLA", "GLB", "GLC", "GLE", "GLS", "EQA", "EQB", "EQC", "EQE", "EQS", "V-Class"],
        "Volkswagen": ["Polo", "Golf", "Jetta", "Passat", "Arteon", "T-Cross", "T-Roc", "Tiguan", "Touareg", "ID.3", "ID.4", "ID.5", "Caddy", "Transporter"],
        "Toyota": ["Yaris", "Corolla", "Camry", "C-HR", "RAV4", "Highlander", "Land Cruiser", "Hilux", "Prius", "Supra", "Avensis", "Auris", "bZ4X"],
        "Honda": ["Civic", "Accord", "CR-V", "HR-V", "Jazz", "Pilot", "City", "e"],
        "Ford": ["Fiesta", "Focus", "Mondeo", "Puma", "Kuga", "EcoSport", "Ranger", "Mustang", "Explorer", "Transit", "Courier"],
        "Opel": ["Corsa", "Astra", "Insignia", "Mokka", "Crossland", "Grandland", "Combo", "Vivaro", "Zafira"],
        "Renault": ["Clio", "Megane", "Talisman", "Captur", "Kadjar", "Koleos", "Symbol", "Taliant", "Austral", "Zoe"],
        "Peugeot": ["108", "208", "308", "408", "508", "2008", "3008", "5008", "Partner"],
        "Fiat": ["Egea", "500", "500X", "Panda", "Tipo", "Doblo", "Fiorino", "Ducato"],
        "Citroën": ["C3", "C4", "C5", "C-Elysée", "Berlingo", "C3 Aircross", "C5 Aircross"],
        "Skoda": ["Fabia", "Octavia", "Superb", "Kamiq", "Karoq", "Kodiaq", "Scala", "Enyaq"],
        "Seat": ["Ibiza", "Leon", "Arona", "Ateca", "Tarraco"],
        "Cupra": ["Formentor", "Leon", "Born", "Ateca"],
        "Hyundai": ["i10", "i20", "i30", "Elantra", "Accent", "Tucson", "Santa Fe", "Kona", "Bayon", "Ioniq 5", "Ioniq 6"],
        "Kia": ["Picanto", "Rio", "Ceed", "Cerato", "Sportage", "Sorento", "Stonic", "Niro", "EV6", "Soul"],
        "Nissan": ["Micra", "Note", "Sentra", "Qashqai", "X-Trail", "Juke", "Navara", "Leaf", "GT-R", "370Z"],
        "Mazda": ["2", "3", "6", "CX-3", "CX-30", "CX-5", "CX-60", "MX-5"],
        "Subaru": ["Impreza", "Legacy", "Forester", "Outback", "XV", "BRZ"],
        "Mitsubishi": ["Space Star", "Lancer", "ASX", "Outlander", "Eclipse Cross", "L200"],
        "Suzuki": ["Swift", "Baleno", "Vitara", "S-Cross", "Jimny", "Ignis"],
        "Volvo": ["S60", "S90", "V40", "V60", "V90", "XC40", "XC60", "XC90", "EX30", "EX90"],
        "Jaguar": ["XE", "XF", "F-Type", "F-Pace", "E-Pace", "I-Pace"],
        "Land Rover": ["Defender", "Discovery", "Discovery Sport", "Range Rover", "Range Rover Sport", "Range Rover Evoque", "Range Rover Velar"],
        "Mini": ["Cooper", "Cooper S", "Countryman", "Clubman", "Electric"],
        "Alfa Romeo": ["Giulia", "Stelvio", "Giulietta", "Tonale"],
        "Porsche": ["911", "718 Cayman", "718 Boxster", "Panamera", "Macan", "Cayenne", "Taycan"],
        "Ferrari": ["Roma", "Portofino", "296", "SF90", "812", "Purosangue"],
        "Lamborghini": ["Huracán", "Urus", "Revuelto"],
        "Maserati": ["Ghibli", "Quattroporte", "Levante", "Grecale", "MC20"],
        "Bentley": ["Continental GT", "Flying Spur", "Bentayga"],
        "Rolls-Royce": ["Phantom", "Ghost", "Wraith", "Cullinan"],
        "Aston Martin": ["Vantage", "DB11", "DBS", "DBX"],
        "Lexus": ["IS", "ES", "LS", "RX", "NX", "UX", "LC", "RC"],
        "Infiniti": ["Q30", "Q50", "Q60", "QX30", "QX50", "QX70"],
        "Chevrolet": ["Spark", "Cruze", "Malibu", "Camaro", "Corvette", "Tahoe", "Silverado", "Equinox"],
        "Cadillac": ["CT4", "CT5", "Escalade", "XT4", "XT5", "XT6", "Lyriq"],
        "Jeep": ["Renegade", "Compass", "Cherokee", "Grand Cherokee", "Wrangler", "Avenger"],
        "Dodge": ["Charger", "Challenger", "Durango", "Ram 1500"],
        "Chrysler": ["300", "Pacifica"],
        "Tesla": ["Model 3", "Model S", "Model X", "Model Y", "Cybertruck"],
        "Polestar": ["Polestar 2", "Polestar 3", "Polestar 4"],
        "Smart": ["Fortwo", "Forfour", "#1"],
        "Dacia": ["Sandero", "Duster", "Logan", "Spring", "Jogger"],
        "DS": ["DS3", "DS4", "DS7", "DS9"],
        "Genesis": ["G70", "G80", "G90", "GV70", "GV80"],
        "Acura": ["ILX", "TLX", "RDX", "MDX", "NSX"],
        "Buick": ["Encore", "Envision", "Enclave"],
        "GMC": ["Terrain", "Acadia", "Yukon", "Sierra"],
        "Lincoln": ["Corsair", "Nautilus", "Aviator", "Navigator"],
        "Isuzu": ["D-Max", "MU-X"],
        "SsangYong": ["Tivoli", "Korando", "Rexton", "Musso"],
        "Tofaş": ["Şahin", "Doğan", "Kartal", "Fiorino"],
        "TOGG": ["T10X"],
        "MG": ["MG3", "MG4", "MG5", "ZS", "HS"],
        "BYD": ["Atto 3", "Dolphin", "Seal", "Han", "Tang"],
        "Geely": ["Coolray", "Emgrand", "Tugella"],
        "Great Wall": ["Haval H6", "Haval Jolion", "Poer"],
        "Chery": ["Tiggo 4", "Tiggo 7", "Tiggo 8", "Arrizo 5"],
    ]
}
