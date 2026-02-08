{
  "indexes": [
    {
      "collectionGroup": "appointments",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "clientId",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "shopId",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "data_agendamento",
          "order": "DESCENDING"
        },
        {
          "fieldPath": "__name__",
          "order": "DESCENDING"
        }
      ],
      "density": "SPARSE_ALL"
    },
    {
      "collectionGroup": "appointments",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "shopId",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "data_agendamento",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "__name__",
          "order": "ASCENDING"
        }
      ],
      "density": "SPARSE_ALL"
    },
    {
      "collectionGroup": "appointments",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "shopId",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "profissionalId",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "data_agendamento",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "__name__",
          "order": "ASCENDING"
        }
      ],
      "density": "SPARSE_ALL"
    },
    {
      "collectionGroup": "users",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "tipo",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "lojasVinculadas",
          "arrayConfig": "CONTAINS"
        },
        {
          "fieldPath": "nome",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "__name__",
          "order": "ASCENDING"
        }
      ],
      "density": "SPARSE_ALL"
    }
  ],
  "fieldOverrides": []
}