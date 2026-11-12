import crypto from "node:crypto";
import { Router } from "express";

import { can } from "../roles.js";
import { savePhoto } from "../uploads.js";

function generateSerialId() {
  const code = crypto.randomBytes(3).toString("hex").toUpperCase();
  return `HH-P-${code}`;
}

export function propertiesRouter(db) {
  const router = Router();

  // Helper to ensure property belongs to current org or user
  async function findScopedProperty(id, req) {
    const numId = Number(id);
    const query = Number.isInteger(numId) ? { id: numId } : { propertySerialId: id };
    const property = await db.findDoc("properties", query);
    if (!property) return null;

    if (req.scope.org_id != null) {
      if (property.org_id !== req.scope.org_id) return null;
    } else {
      if (property.user_id !== req.user.id) return null;
    }
    return property;
  }

  // 1. List properties
  router.get("/", async (req, res, next) => {
    try {
      const filter = req.scope.org_id != null
        ? { org_id: req.scope.org_id }
        : { user_id: req.user.id };
      const list = await db.findDocs("properties", filter);
      const active = list.filter((p) => p.status !== "deleted");
      return res.json(active);
    } catch (err) {
      return next(err);
    }
  });

  // 2. Create draft property (Step 0)
  router.post("/", async (req, res, next) => {
    try {
      const body = req.body || {};
      const propertySerialId =
        body.property_serial_id || body.propertySerialId || generateSerialId();

      const doc = {
        propertySerialId,
        user_id: req.user.id,
        org_id: req.scope.org_id ?? null,
        status: "draft",
        setupMethod: body.setup_method || body.setupMethod || "manual",
        airbnbUrl: body.airbnb_url || body.airbnbUrl || null,
        current_step: body.current_step || body.currentStep || "property_type",
        step_number: body.step_number || body.stepNumber || 1,

        // Step 1: Property Type
        propertyType: body.property_type || body.propertyType || "House",

        // Step 2: Accommodation Type
        accommodationType:
          body.accommodation_type || body.accommodationType || "entireHouse",

        // Step 3: Owner vs Manager
        ownershipType: body.ownership_type || body.ownershipType || "owner",

        // Step 4: Address
        address: body.address || {
          formattedAddress: body.location || "",
          streetName: "",
          aptSuite: "",
          landmark: "",
          city: "",
          state: "",
          postalCode: "",
          country: "India",
        },
        location: body.location || body.address?.formattedAddress || "",

        // Step 5: Photos (>=10 recommended)
        photos: Array.isArray(body.photos) ? body.photos : [],
        coverPhoto: body.cover_photo || body.coverPhoto || null,

        // Step 6: Documents
        documents: Array.isArray(body.documents) ? body.documents : [],

        // Step 7: More details / Capacity
        capacity: body.capacity || {
          guests: body.guests ?? 1,
          bedrooms: body.bedrooms ?? 1,
          beds: body.beds ?? 1,
          bathrooms: body.bathrooms ?? 1,
        },

        // Step 8: Amenities
        amenities: Array.isArray(body.amenities) ? body.amenities : [],

        // Step 9: Uniqueness tags
        uniqueness: Array.isArray(body.uniqueness) ? body.uniqueness : [],

        // Step 10: Experiences
        experiences: Array.isArray(body.experiences) ? body.experiences : [],

        // Step 11: Title & Description
        title: body.title || "",
        description: body.description || body.notes || "",
        videoUrl: body.video_url || body.videoUrl || "",

        // Step 12: Neighbourhood
        neighbourhood: body.neighbourhood || "",

        // Step 13: Base Price
        basePrice: Number(body.base_price ?? body.basePrice ?? body.price ?? 0),
        currency: "INR",

        // Step 14: Check-in / check-out
        checkInTime: body.check_in || body.checkInTime || body.checkIn || "",
        checkOutTime: body.check_out || body.checkOutTime || body.checkOut || "",

        // Step 15: House rules & cancellation
        houseRules: body.house_rules || body.houseRules || {
          childFriendly: true,
          infantFriendly: true,
          petsAllowed: false,
          smokingAllowed: false,
          partiesAllowed: false,
          additionalRules: "",
        },
        instantBooking: body.instant_booking ?? body.instantBooking ?? true,
        cancellationPolicy:
          body.cancellation_policy || body.cancellationPolicy || "flexible",

        // Step 16: Check-in method & caretaker
        checkInMethod:
          body.check_in_method || body.checkInMethod || "host_greets",
        caretaker: {
          name: body.caretaker_name || body.caretaker?.name || "",
          phone: body.caretaker_phone || body.caretaker?.phone || "",
        },
        caretakerName: body.caretaker_name || body.caretaker?.name || "",
        caretakerPhone: body.caretaker_phone || body.caretaker?.phone || "",

        // Step 17: ID Verification status
        accountVerificationStatus:
          body.account_verification_status ||
          body.accountVerificationStatus ||
          "pending",

        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };

      const saved = await db.insertDoc("properties", doc);

      // Log creation
      await db.insertDoc("property_logs", {
        property_id: saved.id,
        propertySerialId: saved.propertySerialId,
        user_id: req.user.id,
        action: "created_draft",
        timestamp: new Date().toISOString(),
      });

      return res.status(201).json(saved);
    } catch (err) {
      return next(err);
    }
  });

  // 3. Get single property
  router.get("/:id", async (req, res, next) => {
    try {
      const property = await findScopedProperty(req.params.id, req);
      if (!property || property.status === "deleted") {
        return res.status(404).json({ detail: "Property not found" });
      }
      return res.json(property);
    } catch (err) {
      return next(err);
    }
  });

  // 4. Update property (any step save / draft update)
  async function handleUpdate(req, res, next) {
    try {
      const property = await findScopedProperty(req.params.id, req);
      if (!property || property.status === "deleted") {
        return res.status(404).json({ detail: "Property not found" });
      }

      const body = req.body || {};
      const updates = { ...body, updated_at: new Date().toISOString() };

      // Never allow overriding id, user_id, or org_id
      delete updates.id;
      delete updates.user_id;
      delete updates.org_id;

      // Normalize snake_case fields from Flutter payload
      if (body.base_price !== undefined) updates.basePrice = Number(body.base_price);
      if (body.property_serial_id !== undefined) updates.propertySerialId = body.property_serial_id;
      if (body.current_step !== undefined) updates.current_step = body.current_step;
      if (body.property_type !== undefined) updates.propertyType = body.property_type;
      if (body.accommodation_type !== undefined) updates.accommodationType = body.accommodation_type;
      if (body.ownership_type !== undefined) updates.ownershipType = body.ownership_type;
      if (body.cover_photo !== undefined) updates.coverPhoto = body.cover_photo;
      if (body.caretaker_name !== undefined) {
        updates.caretakerName = body.caretaker_name;
        updates.caretaker = updates.caretaker || {};
        updates.caretaker.name = body.caretaker_name;
      }
      if (body.caretaker_phone !== undefined) {
        updates.caretakerPhone = body.caretaker_phone;
        updates.caretaker = updates.caretaker || {};
        updates.caretaker.phone = body.caretaker_phone;
      }
      if (body.account_verification_status !== undefined) updates.accountVerificationStatus = body.account_verification_status;
      if (body.house_rules !== undefined) updates.houseRules = body.house_rules;
      if (body.check_in !== undefined) updates.checkInTime = body.check_in;
      if (body.check_out !== undefined) updates.checkOutTime = body.check_out;

      // Lock address fields if activated
      if (property.status === "activated" && updates.address) {
        delete updates.address;
      }

      // Sync location string if address updated
      if (updates.address?.formattedAddress) {
        updates.location = updates.address.formattedAddress;
      }

      const updated = await db.updateDoc("properties", { id: property.id }, updates);

      // Log step transition or edit
      await db.insertDoc("property_logs", {
        property_id: property.id,
        propertySerialId: property.propertySerialId,
        user_id: req.user.id,
        action: "updated_step",
        current_step: updates.current_step || property.current_step,
        timestamp: new Date().toISOString(),
      });

      return res.json(updated);
    } catch (err) {
      return next(err);
    }
  }

  router.put("/:id", handleUpdate);
  router.patch("/:id", handleUpdate);

  // 5. Upload photo for property
  router.post("/:id/photos", async (req, res, next) => {
    try {
      const property = await findScopedProperty(req.params.id, req);
      if (!property || property.status === "deleted") {
        return res.status(404).json({ detail: "Property not found" });
      }

      const result = await savePhoto(`properties/${property.id}`, req.body);
      if (result.error) {
        return res.status(400).json({ detail: result.error });
      }

      const photos = [...(property.photos || []), result.url];
      const updates = { photos, updated_at: new Date().toISOString() };
      if (!property.coverPhoto) {
        updates.coverPhoto = result.url;
      }

      const updated = await db.updateDoc("properties", { id: property.id }, updates);
      return res.json({ url: result.url, photos: updated.photos, coverPhoto: updated.coverPhoto });
    } catch (err) {
      return next(err);
    }
  });

  // 6. Publish property (Step 19)
  router.post("/:id/publish", async (req, res, next) => {
    try {
      const property = await findScopedProperty(req.params.id, req);
      if (!property || property.status === "deleted") {
        return res.status(404).json({ detail: "Property not found" });
      }

      if (req.membership && !can(req.membership.role, "properties.publish")) {
        return res.status(403).json({ detail: "Your role cannot publish properties" });
      }

      // Basic validations
      if (!property.title || property.title.trim().length === 0) {
        return res.status(400).json({ detail: "Property title is required to publish" });
      }
      if (!property.propertyType) {
        return res.status(400).json({ detail: "Property type is required to publish" });
      }

      const activated = await db.updateDoc(
        "properties",
        { id: property.id },
        {
          status: "activated",
          current_step: "publish_property",
          published_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }
      );

      await db.insertDoc("property_logs", {
        property_id: property.id,
        propertySerialId: property.propertySerialId,
        user_id: req.user.id,
        action: "published",
        timestamp: new Date().toISOString(),
      });

      return res.json({ ok: true, property: activated });
    } catch (err) {
      return next(err);
    }
  });

  // 7. Delete / Archive property
  router.delete("/:id", async (req, res, next) => {
    try {
      const property = await findScopedProperty(req.params.id, req);
      if (!property || property.status === "deleted") {
        return res.status(404).json({ detail: "Property not found" });
      }

      if (req.membership && !can(req.membership.role, "properties.delete")) {
        return res.status(403).json({ detail: "Your role cannot delete properties" });
      }

      await db.updateDoc("properties", { id: property.id }, {
        status: "deleted",
        deleted_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });

      return res.status(204).end();
    } catch (err) {
      return next(err);
    }
  });

  // 8. Clone existing property
  router.post("/clone/:id", async (req, res, next) => {
    try {
      const property = await findScopedProperty(req.params.id, req);
      if (!property || property.status === "deleted") {
        return res.status(404).json({ detail: "Original property not found" });
      }

      const newTitle = req.query.title || `${property.title} (Copy)`;
      const cloneDoc = {
        ...property,
        id: undefined,
        propertySerialId: generateSerialId(),
        title: newTitle,
        status: "draft",
        current_step: "property_type",
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };
      delete cloneDoc.id;

      const cloned = await db.insertDoc("properties", cloneDoc);
      return res.status(201).json(cloned);
    } catch (err) {
      return next(err);
    }
  });

  return router;
}

