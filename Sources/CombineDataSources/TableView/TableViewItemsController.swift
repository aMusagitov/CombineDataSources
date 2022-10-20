//
//  For credits and licence check the LICENSE file included in this package.
//  (c) CombineOpenSource, Created by Marin Todorov.
//

import UIKit
import Combine

/// A table view controller acting as data source.
/// `CollectionType` needs to be a collection of collections to represent sections containing rows.
public class TableViewItemsController<CollectionType, CellType>: NSObject, UITableViewDataSource
where CollectionType: RandomAccessCollection,
      CollectionType.Index == Int,
      CollectionType.Element: Hashable,
      CollectionType.Element: RandomAccessCollection,
      CollectionType.Element.Index == Int,
      CollectionType.Element.Element: Hashable,
      CollectionType.Element.Element: Identifiable,
      CellType: UITableViewCell {
    
    public typealias Element = CollectionType.Element.Element
    public typealias CellFactory<Element: Equatable> = (TableViewItemsController<CollectionType, CellType>, UITableView, IndexPath, Element) -> UITableViewCell
    public typealias CellConfig<Element> = (CellType, IndexPath, Element) -> Void
    
    private let cellFactory: CellFactory<Element>
    private let cellConfig: CellConfig<Element>
    private var collection: CollectionType!
    
    /// Should the table updates be animated or static.
    public var animated = true
    
    /// What transitions to use for inserting, updating, and deleting table rows.
    public var rowAnimations = (
        insert: UITableView.RowAnimation.automatic,
        update: UITableView.RowAnimation.automatic,
        delete: UITableView.RowAnimation.automatic
    )
    
    /// The table view for the data source
    weak var tableView: UITableView!
    
    /// A fallback data source to implement custom logic like indexes, dragging, etc.
    public var dataSource: UITableViewDataSource?
    
    // MARK: - Init
    
    /// An initializer that takes a cell type and identifier and configures the controller to dequeue cells
    /// with that data and configures each cell by calling the developer provided `cellConfig()`.
    /// - Parameter cellIdentifier: A cell identifier to use to dequeue cells from the source table view
    /// - Parameter cellType: A type to cast dequeued cells as
    /// - Parameter cellConfig: A closure to call before displaying each cell
    public init(cellIdentifier: String, cellType: CellType.Type, cellConfig: @escaping CellConfig<Element>) {
        cellFactory = { dataSource, tableView, indexPath, value in
            let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as! CellType
            cellConfig(cell, indexPath, value)
            return cell
        }
        self.cellConfig = cellConfig
    }
    
    deinit {
        debugPrint("Controller is released")
    }
    
    // MARK: - Update collection
    private let fromRow = {(section: Int) in return {(row: Int) in return IndexPath(row: row, section: section)}}
    
    func updateCollection(_ items: CollectionType) {
        // Initial collection
        if collection == nil, animated {
            guard tableView.numberOfSections == 0 else {
                // collection is out of sync with the actual table view contents.
                collection = items
                tableView.reloadData()
                return
            }
            
            tableView.beginUpdates()
            tableView.insertSections(IndexSet(integersIn: 0..<items.count), with: rowAnimations.insert)
            for sectionIndex in 0..<items.count {
                let rowAtIndex = fromRow(sectionIndex)
                tableView.insertRows(at: (0..<items[sectionIndex].count).map(rowAtIndex), with: rowAnimations.insert)
            }
            collection = items
            tableView.endUpdates()
        }
        
        // If the changes are not animatable, reload the table
        guard animated, collection != nil, items.count == collection.count else {
            collection = items
            tableView.reloadData()
            return
        }
        
        var deletions: [IndexPath] = []
        var insertions: [IndexPath] = []
        var moves: [(IndexPath, IndexPath)] = []
        
        var notChanged: [IndexPath] = []
        
        items.enumerated().forEach { section, items in
            let rowAtIndex = fromRow(section)
            
            let changesById = delta(newList: items.map { $0.id },
                                    oldList: collection[section].map { $0.id })
            
            let delta = delta(newList: items, oldList: collection[section])
            for row in 0 ..< items.count {
                guard !delta.insertions.contains(row),
                      !delta.removals.contains(row),
                      !delta.moves.contains(where: { $0 == row || $1 == row }) else {
                    continue
                }
                notChanged.append(.init(row: row, section: section))
            }
            
            deletions.append(contentsOf: changesById.removals.map(rowAtIndex))
            insertions.append(contentsOf: changesById.insertions.map(rowAtIndex))
            moves.append(contentsOf: changesById.moves.map { (rowAtIndex($0.0), rowAtIndex($0.1)) })
        }
        
        collection = items
        
        // Commit the changes to the table view sections
        tableView.performBatchUpdates {
            if !deletions.isEmpty {
                tableView.deleteRows(at: deletions, with: rowAnimations.delete)
            }
            
            if !insertions.isEmpty {
                tableView.insertRows(at: insertions, with: rowAnimations.insert)
            }
            
            for move in moves {
                tableView.moveRow(at: move.0, to: move.1)
            }
        } completion: { [weak self] _ in
            guard let indexPathsForVisibleRows = self?.tableView
                .indexPathsForVisibleRows?
                .filter({ !notChanged.contains($0) }) else { return }
            
            indexPathsForVisibleRows.forEach { indexPath in
                guard let self = self,
                      self.collection.count > indexPath.section,
                      self.collection[indexPath.section].count > indexPath.row,
                      let cell = self.tableView.cellForRow(at: indexPath) as? CellType else { return }
                let item = self.collection[indexPath.section][indexPath.row]
                self.cellConfig(cell, indexPath, item)
            }
        }
    }
    
    // MARK: - UITableViewDataSource protocol
    public func numberOfSections(in tableView: UITableView) -> Int {
        guard collection != nil else { return 0 }
        return collection.count
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return collection[section].count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        cellFactory(self, tableView, indexPath, collection[indexPath.section][indexPath.row])
    }
    
    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sectionModel = collection[section] as? Section<CollectionType.Element.Element> else {
            return dataSource?.tableView?(tableView, titleForHeaderInSection: section)
        }
        return sectionModel.header
    }
    
    public func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let sectionModel = collection[section] as? Section<CollectionType.Element.Element> else {
            return dataSource?.tableView?(tableView, titleForFooterInSection: section)
        }
        return sectionModel.footer
    }
    
    // MARK: - Fallback data source object
    override public func forwardingTarget(for aSelector: Selector!) -> Any? {
        return dataSource
    }
}

internal func delta<T>(newList: T, oldList: T) -> (insertions: [Int], removals: [Int], moves: [(Int, Int)])
    where T: RandomAccessCollection, T.Element: Hashable {
        
        let changes = newList.difference(from: oldList).inferringMoves()
        
        var insertions = [Int]()
        var removals = [Int]()
        var moves = [(Int, Int)]()
        
        for change in changes {
            switch change {
            case .insert(offset: let index, element: _, associatedWith: let associatedIndex):
                if let fromIndex = associatedIndex {
                    moves.append((fromIndex, index))
                } else {
                    insertions.append(index)
                }
            case .remove(offset: let index, element: _, associatedWith: let associatedIndex):
                if associatedIndex == nil {
                    removals.append(index)
                }
            }
        }
        return (insertions: insertions, removals: removals, moves: moves)
}
