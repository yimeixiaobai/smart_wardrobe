import SwiftUI
import SwiftData

struct CategoryManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Category> { $0.parent == nil },
           sort: \Category.sortOrder)
    private var topCategories: [Category]

    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var selectedParent: Category?
    @State private var categoryToDelete: Category?
    @State private var showDeleteWarning = false

    var body: some View {
        List {
            ForEach(topCategories) { parent in
                Section {
                    ForEach(parent.sortedChildren) { child in
                        HStack {
                            Text(child.name)
                            Spacer()
                            Text("\(child.clothingItems.count)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            if child.isSystem {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .deleteDisabled(child.isSystem)
                    }
                    .onDelete { indices in
                        deleteChildren(of: parent, at: indices)
                    }
                    .onMove { indices, destination in
                        moveChildren(of: parent, from: indices, to: destination)
                    }

                    Button {
                        selectedParent = parent
                        newCategoryName = ""
                        showingAddCategory = true
                    } label: {
                        Label("添加子分类", systemImage: "plus")
                            .foregroundStyle(Color.accentColor)
                    }
                } header: {
                    HStack {
                        Image(systemName: parent.icon)
                        Text(parent.name)
                    }
                }
            }
            .onMove { indices, destination in
                moveTopCategories(from: indices, to: destination)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("分类管理")
        .alert("该分类下有衣物", isPresented: $showDeleteWarning) {
            Button("删除并归入上级", role: .destructive) {
                if let cat = categoryToDelete, let parent = cat.parent {
                    for item in cat.clothingItems {
                        item.category = parent
                    }
                    modelContext.delete(cat)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let cat = categoryToDelete {
                Text("「\(cat.name)」下有 \(cat.clothingItems.count) 件衣物，删除后将自动归入「\(cat.parent?.name ?? "")」")
            }
        }
        .alert("添加分类", isPresented: $showingAddCategory) {
            TextField("分类名称", text: $newCategoryName)
            Button("取消", role: .cancel) {}
            Button("添加") {
                addSubCategory()
            }
        } message: {
            if let parent = selectedParent {
                Text("在「\(parent.name)」下添加子分类")
            }
        }
    }

    private func moveTopCategories(from source: IndexSet, to destination: Int) {
        var ordered = topCategories.sorted { $0.sortOrder < $1.sortOrder }
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, cat) in ordered.enumerated() {
            cat.sortOrder = index
        }
    }

    private func deleteChildren(of parent: Category, at indices: IndexSet) {
        let children = parent.sortedChildren
        for index in indices {
            let child = children[index]
            if child.clothingItems.count > 0 {
                categoryToDelete = child
                showDeleteWarning = true
            } else {
                modelContext.delete(child)
            }
        }
    }

    private func moveChildren(of parent: Category, from source: IndexSet, to destination: Int) {
        var ordered = parent.sortedChildren
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, cat) in ordered.enumerated() {
            cat.sortOrder = index
        }
    }

    private func addSubCategory() {
        guard let parent = selectedParent,
              !newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let sortOrder = parent.children.count
        let child = Category(
            name: newCategoryName.trimmingCharacters(in: .whitespaces),
            icon: parent.icon,
            sortOrder: sortOrder,
            isSystem: false,
            parent: parent
        )
        modelContext.insert(child)
    }
}
